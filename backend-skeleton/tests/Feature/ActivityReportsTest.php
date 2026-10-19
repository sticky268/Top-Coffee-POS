<?php

namespace Tests\Feature;

use App\Models\{Branch, Business, Category, Order, Product, User};
use App\Services\Reports\ReportMoney;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Spatie\Permission\Models\Permission;
use Tests\TestCase;

class ActivityReportsTest extends TestCase
{
    use RefreshDatabase;
    private Branch $branch;
    private User $owner;
    private User $peer;
    protected function setUp(): void
    {
        parent::setUp();
        $this->travelTo(now()->setTimezone('UTC')->setDate(2026, 10, 19)->setTime(2, 0));
        $business = Business::factory()->create();
        $this->branch = Branch::factory()->create(['business_id' => $business->id, 'timezone' => 'Asia/Phnom_Penh']);
        $this->owner = User::factory()->create(['business_id' => $business->id, 'name' => 'Owner cashier']);
        $this->peer = User::factory()->create(['business_id' => $business->id, 'name' => 'Refund operator']);
        foreach ([$this->owner, $this->peer] as $u) $u->branches()->attach($this->branch->id);
        $this->owner->givePermissionTo(Permission::findOrCreate('reports.view'));
        $this->actingAs($this->owner);
    }
    private function sale(array $values = [], string $at = '2026-10-19 00:00:00', bool $paid = true): int
    {
        $values += ['uuid' => (string) Str::uuid(), 'branch_id' => $this->branch->id, 'user_id' => $this->owner->id,
            'order_type' => 'takeaway', 'status' => 'completed', 'subtotal' => '10.00', 'total' => '10.00',
            'discount_total' => '0.00', 'tax_total' => '0.00', 'supplemental_total' => '0.00',
            'completed_at' => $at, 'created_at' => $at, 'updated_at' => $at];
        $id = DB::table('orders')->insertGetId($values);
        if ($paid) DB::table('payments')->insert(['order_id' => $id, 'amount' => ReportMoney::decimal(
            ReportMoney::cents($values['total']) + ReportMoney::cents($values['supplemental_total'])),
            'method' => 'cash', 'status' => 'completed', 'processed_by' => $values['user_id'], 'created_at' => $at, 'updated_at' => $at]);
        return $id;
    }
    private function report(array $input = [])
    {
        return $this->getJson('/api/v1/reports/sales?'.http_build_query($input + ['report' => 'activity', 'branch_id' => $this->branch->id]));
    }
    private function voidEvent(int $order, string $at): void
    {
        DB::table('audit_logs')->insert(['business_id' => $this->owner->business_id, 'user_id' => $this->peer->id,
            'action' => 'order.cancelled', 'auditable_type' => (new Order)->getMorphClass(), 'auditable_id' => $order,
            'created_at' => $at, 'updated_at' => $at]);
    }
    public function test_time_cells_reconcile_exact_cohort_money_and_exclude_unpaid_orders(): void
    {
        $order = $this->sale(['supplemental_total' => '2.00', 'discount_total' => '1.00', 'tax_total' => '0.90'], '2026-10-18 17:00:00');
        $payment = DB::table('payments')->where('order_id', $order)->value('id');
        DB::table('payment_refunds')->insert(['payment_id' => $payment, 'amount' => '1.01', 'reason' => 'Correction',
            'processed_by' => $this->peer->id, 'created_at' => '2026-10-25 00:00:00', 'updated_at' => '2026-10-25 00:00:00']);
        DB::table('payments')->where('id', $payment)->update(['status' => 'partially_refunded']);
        $this->sale(['total' => '0.01']);
        $this->sale(['total' => '99.00'], '2026-10-19 00:00:00', false);
        $this->sale(['total' => '2.00'], '2026-10-18 16:59:59');
        $data = $this->report()->assertOk()->assertJsonCount(168, 'data.cells')
            ->assertJsonPath('data.summary.orders', 2)->assertJsonPath('data.summary.sales', '12.01')
            ->assertJsonPath('data.summary.net_sales', '11.00')->assertJsonPath('data.summary.comparisons.net_sales.previous', '2.00')->json('data');
        foreach (['sales', 'discounts', 'refunds', 'net_sales'] as $key) {
            foreach (['cells', 'cashiers'] as $group) $this->assertSame(ReportMoney::cents($data['summary'][$key]),
                array_sum(array_map(fn ($r) => ReportMoney::cents($r[$key]), $data[$group])));
        }
        $this->assertSame('10.99', $data['cells'][0]['net_sales']);
        $this->report(['detail' => 'activity', 'weekday' => 1, 'hour' => 0, 'activity_kind' => 'refunds'])
            ->assertOk()->assertJsonCount(1, 'data.rows')->assertJsonPath('data.rows.0.order_id', $order)
            ->assertJsonPath('data.rows.0.actors.0', 'Refund operator')->assertJsonPath('data.rows.0.occurred_at_local', '2026-10-19 00:00:00 +07:00');
    }
    public function test_voids_use_first_audit_event_and_preserve_owner_actor_distinction(): void
    {
        $void = $this->sale(['status' => 'cancelled', 'completed_at' => null], '2026-10-10 00:00:00', false);
        $this->voidEvent($void, '2026-10-18 17:00:00');
        $this->voidEvent($void, '2026-10-19 02:00:00');
        $this->sale(['status' => 'cancelled', 'completed_at' => null], '2026-10-19 00:00:00', false); // Legacy without evidence.
        $old = $this->sale(['status' => 'cancelled', 'completed_at' => null], '2026-10-10 00:00:00', false);
        $this->voidEvent($old, '2026-10-17 00:00:00');
        $this->voidEvent($old, '2026-10-19 00:00:00');
        $this->report()->assertOk()->assertJsonPath('data.summary.voids', 1)->assertJsonPath('data.summary.voids_rate', '100.00')
            ->assertJsonCount(0, 'data.cashiers.0.flags');
        $this->report(['detail' => 'activity', 'activity_kind' => 'voids'])->assertOk()->assertJsonCount(1, 'data.rows')
            ->assertJsonPath('data.rows.0.cashier_id', $this->owner->id)->assertJsonPath('data.rows.0.actors.0', $this->peer->name);
    }
    public function test_repeated_dst_hours_are_combined_without_losing_sales(): void
    {
        $this->branch->update(['timezone' => 'America/New_York']);
        foreach (['2026-11-01 05:30:00', '2026-11-01 06:30:00'] as $at) $this->sale([], $at);
        $data = $this->report(['period' => 'custom', 'date_from' => '2026-11-01', 'date_to' => '2026-11-01'])
            ->assertOk()->assertJsonPath('data.summary.orders', 2)->json('data');
        $cell = collect($data['cells'])->first(fn ($r) => $r['weekday'] === 7 && $r['hour'] === 1);
        $this->assertSame(2, $cell['orders']);
        $this->report(['period' => 'custom', 'date_from' => '2026-11-01', 'date_to' => '2026-11-01', 'detail' => 'activity', 'weekday' => 7, 'hour' => 1])
            ->assertOk()->assertJsonCount(2, 'data.rows')->assertJsonPath('data.rows.0.occurred_at_local', '2026-11-01 01:30:00 -04:00')
            ->assertJsonPath('data.rows.1.occurred_at_local', '2026-11-01 01:30:00 -05:00');
    }
    public function test_combined_branches_use_each_local_hour_including_fractional_offsets(): void
    {
        $second = Branch::factory()->create(['business_id' => $this->owner->business_id, 'timezone' => 'Asia/Kathmandu']);
        $this->owner->branches()->attach($second->id);
        $this->sale([], '2026-10-18 17:00:00');
        $this->sale(['branch_id' => $second->id], '2026-10-18 18:15:00');
        $foreign = Branch::factory()->create();
        $this->sale(['branch_id' => $foreign->id], '2026-10-19 00:00:00');
        $this->getJson('/api/v1/reports/sales?report=activity&period=custom&date_from=2026-10-19&date_to=2026-10-19')
            ->assertOk()->assertJsonPath('data.summary.orders', 2)->assertJsonPath('data.cells.0.orders', 2)->assertJsonCount(2, 'data.meta.branches');
    }

    public function test_flags_require_samples_and_peer_baseline_ignores_only_cashier_filter(): void
    {
        for ($i = 0; $i < 20; $i++) {
            $this->sale(['discount_total' => $i < 10 ? '1.00' : '0.00']);
            $this->sale(['user_id' => $this->peer->id]);
        }
        $low = User::factory()->create(['business_id' => $this->owner->business_id]);
        $low->branches()->attach($this->branch->id);
        for ($i = 0; $i < 19; $i++) $this->sale(['user_id' => $low->id, 'discount_total' => '1.00']);
        // This cashier's extreme rate raises the peer baseline; no misleading flag for owner.
        $this->report(['cashier_id' => $this->owner->id])->assertOk()->assertJsonCount(0, 'data.cashiers.0.flags');
        $this->report(['cashier_id' => $low->id])->assertOk()->assertJsonCount(0, 'data.cashiers.0.flags');
        DB::table('orders')->where('user_id', $low->id)->update(['deleted_at' => now()]);
        $this->report(['cashier_id' => $this->owner->id])->assertOk()->assertJsonPath('data.cashiers.0.flags.0', 'discounted_orders')
            ->assertJsonPath('data.cashiers.0.discounted_orders_rate', '50.00');
    }
    public function test_permissions_category_scope_and_source_pagination(): void
    {
        $category = Category::create(['business_id' => $this->owner->business_id, 'name' => 'Coffee', 'is_active' => true]);
        $product = Product::create(['business_id' => $this->owner->business_id, 'category_id' => $category->id, 'name' => 'Latte', 'base_price' => '10.00', 'is_active' => true]);
        for ($i = 0; $i < 51; $i++) {
            $id = $this->sale();
            DB::table('order_items')->insert(['order_id' => $id, 'product_id' => $product->id, 'product_name' => 'Latte', 'quantity' => 1, 'unit_price' => '10.00']);
        }
        $this->sale(); // Excluded from category selection.
        $this->report(['category_id' => $category->id, 'detail' => 'activity', 'page' => 2])->assertOk()
            ->assertJsonPath('data.total', 51)->assertJsonCount(1, 'data.rows');
        $other = Branch::factory()->create();
        $this->report(['branch_id' => $other->id])->assertForbidden();
        $this->report(['cashier_id' => User::factory()->create()->id])->assertForbidden();
        $this->report(['hour' => 24])->assertUnprocessable();
        $this->report(['weekday' => 0])->assertUnprocessable();
        $this->owner->revokePermissionTo('reports.view');
        $this->report()->assertForbidden();
    }
    public function test_pinned_calendar_comparison_and_previous_only_cashier_remain_visible(): void
    {
        $this->sale(['user_id' => $this->peer->id], '2026-09-05 01:00:00');
        $this->sale();
        $r = $this->report(['period' => 'custom', 'date_from' => '2026-10-01', 'date_to' => '2026-10-19',
            'comparison_from' => '2026-09-01', 'comparison_to' => '2026-09-19'])->assertOk();
        $row = collect($r->json('data.cashiers'))->firstWhere('id', $this->peer->id);
        $this->assertSame(0, $row['orders']);
        $this->assertSame('-100.00', $row['comparisons']['orders']['percent']);
        $this->assertSame('2026-09-01', $r->json('data.meta.previous_from'));
    }
}
