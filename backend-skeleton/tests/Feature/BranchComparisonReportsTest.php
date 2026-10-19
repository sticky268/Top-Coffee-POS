<?php

namespace Tests\Feature;

use App\Models\{Branch, Business, Category, Product, User, Order, OrderItem, RecipeItem, Unit, Ingredient, ProductVariant, Modifier, ModifierGroup, OrderItemModifier};
use App\Services\{SaleInventoryService, StockMovementService};
use App\Services\Reports\ReportAllocation;
use App\Services\Reports\ReportMoney;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Spatie\Permission\Models\Permission;
use Tests\TestCase;

class BranchComparisonReportsTest extends TestCase
{
    use RefreshDatabase;
    private Branch $branch;
    private User $actor;
    private Category $category;
    private Product $product;

    protected function setUp(): void
    {
        parent::setUp();
        $this->travelTo(now()->setTimezone('UTC')->setDate(2026, 10, 19)->setTime(2, 0));
        $business = Business::factory()->create();
        $this->branch = Branch::factory()->create(['business_id' => $business->id, 'timezone' => 'Asia/Phnom_Penh']);
        $this->actor = User::factory()->create(['business_id' => $business->id]);
        $this->actor->branches()->attach($this->branch->id);
        $this->actor->givePermissionTo(Permission::findOrCreate('reports.view'));
        $this->actingAs($this->actor);
        $this->category = Category::create(['business_id' => $business->id, 'name' => 'Coffee', 'is_active' => true]);
        $this->product = $this->product('Latte');
    }

    private function product(string $name): Product
    {
        $product = Product::create(['business_id' => $this->actor->business_id, 'category_id' => $this->category->id,
            'name' => $name, 'base_price' => '10.00', 'is_active' => true]);
        $product->branches()->attach($this->branch->id, ['is_available' => true]);
        return $product;
    }

    private function sale(array $values = [], string $at = '2026-10-19 01:00:00', bool $paid = true): int
    {
        $id = DB::table('orders')->insertGetId($values + ['uuid' => (string) Str::uuid(), 'branch_id' => $this->branch->id,
            'user_id' => $this->actor->id, 'order_type' => 'takeaway', 'status' => 'completed', 'subtotal' => '10.00',
            'discount_total' => '0.00', 'tax_total' => '0.00', 'total' => '10.00', 'supplemental_total' => '0.00',
            'completed_at' => $at, 'created_at' => $at, 'updated_at' => $at]);
        if ($paid) DB::table('payments')->insert(['order_id' => $id, 'method' => 'cash', 'amount' => $values['paid'] ?? '10.00',
            'status' => 'completed', 'processed_by' => $this->actor->id, 'created_at' => $at, 'updated_at' => $at]);
        return $id;
    }

    private function item(int $order, ?string $cost = '2.000000', array $values = []): int
    {
        return DB::table('order_items')->insertGetId($values + ['order_id' => $order, 'product_id' => $this->product->id,
            'product_name' => 'Latte', 'quantity' => 1, 'unit_price' => '10.00', 'ingredient_cost' => $cost,
            'sale_category_captured' => true, 'sale_category_id' => $this->category->id, 'sale_category_name' => 'Coffee']);
    }

    private function report(array $filters = [])
    {
        return $this->getJson('/api/v1/reports/sales?'.http_build_query($filters + ['report' => 'branches', 'period' => 'custom', 'date_from' => '2026-10-19', 'date_to' => '2026-10-19']));
    }

    private function refund(int $order, string $amount, string $disposition = 'consumed'): void
    {
        $payment = DB::table('payments')->where('order_id', $order)->value('id');
        DB::table('payments')->where('id', $payment)->update(['status' => 'partially_refunded']);
        DB::table('payment_refunds')->insert(['payment_id' => $payment, 'amount' => $amount,
            'reason' => 'Correction', 'inventory_disposition' => $disposition, 'processed_by' => $this->actor->id,
            'created_at' => '2026-10-20 01:00:00', 'updated_at' => '2026-10-20 01:00:00']);
    }

    private function branch(string $name, string $timezone = 'Asia/Phnom_Penh'): Branch
    {
        $branch = Branch::factory()->create(['business_id' => $this->actor->business_id, 'name' => $name, 'timezone' => $timezone]);
        $this->actor->branches()->attach($branch->id);
        return $branch;
    }

    public function test_branch_totals_growth_and_costs_reconcile_with_profit_and_sources(): void
    {
        $second = $this->branch('Airport');
        $zero = $this->branch('Quiet');
        $prior = $this->branch('Previous only');
        $this->item($this->sale(), '0.123456');
        $this->item($this->sale([], '2026-10-18 01:00:00'), '0.100000');
        $this->item($this->sale(['branch_id' => $second->id]), '1.000001');
        $this->item($this->sale(['branch_id' => $prior->id], '2026-10-18 01:00:00'));
        $this->item($this->sale([], '2026-10-19 01:00:00', false));
        $this->item($this->sale(['status' => 'cancelled']));
        $order = $this->sale(['status' => 'new']);
        $this->item($order);
        $r = $this->report()->assertOk()->assertJsonCount(4, 'data.branches')
            ->assertJsonPath('data.summary.revenue', '20.00')->assertJsonPath('data.summary.cogs', '1.123457')->json('data');
        $rows = collect($r['branches'])->keyBy('id');
        $this->assertSame('0.00', $rows[$zero->id]['revenue']);
        $this->assertSame('-100.00', $rows[$prior->id]['comparisons']['revenue']['percent']);
        $this->assertSame('new', $rows[$second->id]['comparisons']['revenue']['status']);
        $this->assertSame(1, $rows[$second->id]['revenue_rank']);
        $this->assertSame(1, $rows[$this->branch->id]['revenue_rank']);
        $this->assertSame('50.00', $rows[$second->id]['revenue_share_percent']);
        foreach (['revenue', 'cogs', 'gross_profit'] as $key) {
            $profit = $this->report(['report' => 'profit'])->assertOk()->json('data.summary.'.$key);
            $this->assertSame($profit, $r['summary'][$key]);
        }
        $this->report(['report' => 'profit', 'detail' => 'profit', 'branch_id' => $second->id])
            ->assertOk()->assertJsonPath('data.total', 1)->assertJsonPath('data.rows.0.branch_id', $second->id)
            ->assertJsonPath('data.rows.0.cogs', '1.000001');
    }

    public function test_local_midnights_pinned_month_baseline_refunds_and_unknown_costs(): void
    {
        $ny = $this->branch('New York', 'America/New_York');
        $this->item($this->sale([], '2026-10-18 17:00:00'), null); // Phnom Penh midnight.
        $this->item($this->sale(['branch_id' => $ny->id], '2026-10-19 03:59:59')); // NY previous day.
        $id = $this->sale(['branch_id' => $ny->id], '2026-10-19 04:00:00');
        $this->item($id);
        $this->refund($id, '5.00'); // Adjusts original sale even on following date.
        $this->item($this->sale(['branch_id' => $ny->id], '2026-09-10 04:00:00'));
        $r = $this->report()->assertOk()->assertJsonPath('data.summary.revenue', '15.00')
            ->assertJsonPath('data.summary.cogs', null)->assertJsonPath('data.summary.gross_profit', null)->json('data');
        $rows = collect($r['branches'])->keyBy('id');
        $this->assertSame('5.00', $rows[$ny->id]['revenue']);
        $this->assertSame('5.00', $rows[$ny->id]['refunds']);
        $this->assertSame('2.000000', $rows[$ny->id]['cogs']);
        $this->assertSame('33.33', $rows[$ny->id]['revenue_share_percent']);
        $this->report(['date_from' => '2026-10-01', 'comparison_from' => '2026-09-01', 'comparison_to' => '2026-09-19'])
            ->assertOk()->assertJsonPath('data.meta.previous_from', '2026-09-01')
            ->assertJsonPath('data.summary.comparisons.revenue.previous', '10.00');
    }

    public function test_historical_category_cashier_and_authorization_are_enforced(): void
    {
        $hidden = Branch::factory()->create(['business_id' => $this->actor->business_id]);
        $foreign = Branch::factory()->create();
        $this->item($this->sale(['branch_id' => $hidden->id]));
        $this->item($this->sale(), '1.000001');
        $this->item($this->sale(), null, ['sale_category_captured' => false, 'sale_category_id' => null]);
        $this->report(['category_id' => $this->category->id, 'cashier_id' => $this->actor->id])->assertOk()
            ->assertJsonCount(1, 'data.branches')->assertJsonPath('data.summary.revenue', '10.00')
            ->assertJsonPath('data.summary.cogs', '1.000001');
        $this->report(['branch_id' => $hidden->id])->assertForbidden();
        $this->report(['branch_id' => $foreign->id])->assertForbidden();
        $this->report(['cashier_id' => User::factory()->create()->id])->assertForbidden();
        $this->actor->givePermissionTo(Permission::findOrCreate('branches.view-all'));
        $this->report()->assertOk()->assertJsonCount(2, 'data.branches');
        $this->report(['branch_id' => $foreign->id])->assertForbidden();
        $this->report(['detail' => 'profit'])->assertUnprocessable();
        $this->report(['comparison_from' => '2026-10-19', 'comparison_to' => '2026-10-19'])->assertUnprocessable();
        $this->actor->revokePermissionTo('reports.view');
        $this->report()->assertForbidden();
    }

    public function test_zero_revenue_has_no_rank_or_share_and_archived_branches_remain_visible(): void
    {
        $archived = $this->branch('Archived');
        $archived->delete();
        $this->report()->assertOk()->assertJsonCount(2, 'data.branches')
            ->assertJsonPath('data.branches.0.revenue_rank', null)
            ->assertJsonPath('data.branches.0.revenue_share_percent', null)
            ->assertJsonPath('data.summary.margin_percent', null);
        $this->actor->branches()->detach();
        $this->report()->assertOk()->assertJsonCount(0, 'data.branches')->assertJsonPath('data.summary.revenue', '0.00');
    }

    public function test_negative_legacy_revenue_does_not_generate_misleading_shares(): void
    {
        $this->item($this->sale(['tax_total' => '20.00']));
        $this->report()->assertOk()->assertJsonPath('data.summary.revenue', '-10.00')
            ->assertJsonPath('data.branches.0.revenue_share_percent', null);
        $other = $this->branch('Positive');
        $this->item($this->sale(['branch_id' => $other->id]));
        $this->item($this->sale(['branch_id' => $other->id]));
        $this->report()->assertOk()->assertJsonPath('data.summary.revenue', '10.00')
            ->assertJsonPath('data.branches.0.revenue_share_percent', null)
            ->assertJsonPath('data.branches.1.revenue_share_percent', null);
    }

    public function test_many_branches_are_batched_without_per_branch_queries(): void
    {
        for ($i = 0; $i < 12; $i++) {
            $branch = $this->branch('Branch '.$i);
            $this->item($this->sale(['branch_id' => $branch->id]));
        }
        DB::enableQueryLog();
        $this->report()->assertOk()->assertJsonCount(13, 'data.branches')->assertJsonPath('data.summary.revenue', '120.00');
        $this->assertLessThan(30, count(DB::getQueryLog()));
        DB::disableQueryLog();
    }
}
