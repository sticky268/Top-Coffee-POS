<?php

namespace Tests\Feature;

use App\Models\Branch;
use App\Models\Business;
use App\Models\User;
use App\Services\Reports\ReportMoney;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Spatie\Permission\Models\Permission;
use Tests\TestCase;

class SalesReportsTest extends TestCase
{
    use RefreshDatabase;

    private Branch $branch;
    private User $manager;

    protected function setUp(): void
    {
        parent::setUp();
        $this->travelTo(now()->setTimezone('UTC')->setDate(2026, 10, 18)->setTime(18, 30));
        $business = Business::factory()->create();
        $this->branch = Branch::factory()->create(['business_id' => $business->id, 'timezone' => 'Asia/Phnom_Penh']);
        $this->manager = User::factory()->create(['business_id' => $business->id]);
        $this->manager->givePermissionTo(Permission::findOrCreate('reports.view'));
        $this->manager->branches()->attach($this->branch->id);
        $this->actingAs($this->manager);
    }

    private function sale(string $at, string $total = '10.00', array $extra = [], bool $paid = true): int
    {
        $id = DB::table('orders')->insertGetId(array_merge([
            'uuid' => (string) Str::uuid(), 'branch_id' => $this->branch->id, 'user_id' => $this->manager->id,
            'order_type' => 'takeaway', 'status' => 'completed', 'subtotal' => $total, 'total' => $total,
            'discount_total' => '0.00', 'tax_total' => '0.00', 'supplemental_total' => '0.00',
            'created_at' => $at, 'updated_at' => $at, 'completed_at' => $at,
        ], $extra));
        if ($paid) $this->payment($id, $total, $at);
        return $id;
    }

    private function payment(int $order, string $amount, string $at, string $method = 'cash', ?int $shift = null): int
    {
        return DB::table('payments')->insertGetId(['order_id' => $order, 'method' => $method,
            'amount' => $amount, 'status' => 'completed', 'processed_by' => $this->manager->id,
            'shift_id' => $shift, 'created_at' => $at, 'updated_at' => $at]);
    }

    private function refund(int $payment, string $amount, string $at, ?int $shift = null): void
    {
        DB::table('payment_refunds')->insert(['payment_id' => $payment, 'amount' => $amount,
            'reason' => 'Receipt correction', 'processed_by' => $this->manager->id,
            'shift_id' => $shift, 'created_at' => $at, 'updated_at' => $at]);
        DB::table('payments')->where('id', $payment)->update(['status' => 'partially_refunded']);
    }

    private function url(array $query = []): string
    {
        return '/api/v1/reports/sales?'.http_build_query(['branch_id' => $this->branch->id] + $query);
    }

    public function test_top_products_group_normalized_snapshot_names_under_strict_sql(): void
    {
        if (DB::getDriverName() === 'mysql') {
            $mode = DB::selectOne('SELECT @@SESSION.sql_mode AS modes')->modes;
            $this->assertStringContainsString('ONLY_FULL_GROUP_BY', $mode);
        }
        $category = DB::table('categories')->insertGetId(['business_id' => $this->manager->business_id,
            'name' => 'Coffee', 'created_at' => now(), 'updated_at' => now()]);
        $product = DB::table('products')->insertGetId(['business_id' => $this->manager->business_id, 'category_id' => $category,
            'name' => 'Current name', 'base_price' => '0.10', 'created_at' => now(), 'updated_at' => now()]);
        $other = DB::table('products')->insertGetId(['business_id' => $this->manager->business_id, 'category_id' => $category,
            'name' => 'Another product', 'base_price' => '0.10', 'created_at' => now(), 'updated_at' => now()]);
        foreach ([[$product, null, 1], [$product, '', 2], [$product, 'Current name', 3],
            [$product, 'Historical name', 4], [$other, 'Current name', 5]] as [$id, $name, $quantity]) {
            $order = $this->sale('2026-10-19 01:00:00');
            DB::table('order_items')->insert(['order_id' => $order, 'product_id' => $id,
                'product_name' => $name, 'quantity' => $quantity, 'unit_price' => '0.10',
                'created_at' => now(), 'updated_at' => now()]);
        }
        // Neither unpaid nor out-of-period lines may enter the aggregation.
        foreach ([$this->sale('2026-10-19 01:00:00', paid: false), $this->sale('2026-10-17 01:00:00')] as $order) {
            DB::table('order_items')->insert(['order_id' => $order, 'product_id' => $product,
                'product_name' => 'Current name', 'quantity' => 100, 'unit_price' => '0.10']);
        }
        $rows = $this->getJson($this->url())->assertOk()->assertJsonCount(3, 'data.top_products')->json('data.top_products');
        $this->assertSame(['Current name', 'Current name', 'Historical name'], array_column($rows, 'product_name'));
        $this->assertSame([6, 5, 4], array_column($rows, 'quantity'));
        $this->assertSame(['0.60', '0.50', '0.40'], array_column($rows, 'total'));
        $this->assertEquals([$product, $other, $product], array_column($rows, 'product_id'));
        DB::table('products')->where('id', $product)->update(['name' => 'Renamed catalogue', 'deleted_at' => now()]);
        $rows = collect($this->getJson($this->url())->assertOk()->json('data.top_products'))->keyBy('product_name');
        $this->assertSame(3, $rows['Renamed catalogue']['quantity']);
        $this->assertSame(4, $rows['Historical name']['quantity']);
    }

    public function test_history_counts_paid_orders_once_and_preserves_whole_order_item_quantities(): void
    {
        $coffee = DB::table('categories')->insertGetId(['business_id' => $this->manager->business_id, 'name' => 'Coffee']);
        $food = DB::table('categories')->insertGetId(['business_id' => $this->manager->business_id, 'name' => 'Food']);
        $latte = DB::table('products')->insertGetId(['business_id' => $this->manager->business_id,
            'category_id' => $coffee, 'name' => 'Latte', 'base_price' => '1.00']);
        $toast = DB::table('products')->insertGetId(['business_id' => $this->manager->business_id,
            'category_id' => $food, 'name' => 'Toast', 'base_price' => '1.00']);
        $other = User::factory()->create(['business_id' => $this->manager->business_id]);
        $other->branches()->attach($this->branch->id);
        $first = $this->sale('2026-10-19 01:00:00', '11.11');
        $second = $this->sale('2026-10-19 02:00:00', '2.22', ['user_id' => $other->id]);
        $this->sale('2026-10-19 03:00:00', '1.00'); // Legacy paid sale with no items still counts.
        $unpaid = $this->sale('2026-10-19 01:00:00', '100.00', paid: false);
        $foreign = $this->sale('2026-10-19 01:00:00', '100.00', ['branch_id' => Branch::factory()->create()->id]);
        foreach ([[$first, $latte, 2], [$first, $toast, 3], [$second, $toast, 7], [$unpaid, $latte, 100], [$foreign, $latte, 100]] as [$order, $product, $quantity]) {
            DB::table('order_items')->insert(['order_id' => $order, 'product_id' => $product, 'quantity' => $quantity, 'unit_price' => '1.00']);
        }
        $payment = DB::table('payments')->where('order_id', $first)->value('id');
        $this->refund($payment, '1.00', '2026-10-20 01:00:00');
        $this->getJson($this->url())->assertOk()->assertJsonPath('data.timeline.0.total', '14.33')
            ->assertJsonPath('data.timeline.0.orders', 3)->assertJsonPath('data.timeline.0.items', 12);
        $this->getJson($this->url(['category_id' => $coffee]))->assertOk()->assertJsonPath('data.timeline.0.total', '11.11')
            ->assertJsonPath('data.timeline.0.orders', 1)->assertJsonPath('data.timeline.0.items', 5);
        $this->getJson($this->url(['cashier_id' => $other->id]))->assertOk()->assertJsonPath('data.timeline.0.total', '2.22')
            ->assertJsonPath('data.timeline.0.orders', 1)->assertJsonPath('data.timeline.0.items', 7);
        $this->getJson($this->url(['period' => 'year', 'year' => 2026]))->assertOk()->assertJsonCount(12, 'data.timeline')
            ->assertJsonPath('data.timeline.9.total', '14.33')->assertJsonPath('data.timeline.9.orders', 3)
            ->assertJsonPath('data.timeline.9.items', 12)->assertJsonPath('data.timeline.10.upcoming', true)
            ->assertJsonPath('data.timeline.10.orders', 0)->assertJsonPath('data.timeline.10.items', 0);
    }

    public function test_server_presets_follow_branch_date_and_exact_boundaries(): void
    {
        // Server is October 18 UTC, but the branch is already on October 19.
        $this->sale('2026-10-18 16:59:59', '1.00');
        $this->sale('2026-10-18 17:00:00', '2.00');
        $this->sale('2026-10-19 17:00:00', '4.00');
        $this->getJson($this->url())->assertOk()
            ->assertJsonPath('data.meta.date_from', '2026-10-19')
            ->assertJsonPath('data.summary.total_sales', '2.00')
            ->assertJsonPath('data.comparisons.total_sales.previous', '1.00')
            ->assertJsonPath('data.comparisons.total_sales.percent', '100.00');
    }

    public function test_twelve_calendar_months_and_leap_february_are_navigable(): void
    {
        $this->sale('2024-02-29 16:59:59', '12.34');
        $this->sale('2024-02-29 17:00:00', '45.67');
        $this->getJson($this->url(['period' => 'year', 'year' => 2024]))->assertOk()
            ->assertJsonCount(12, 'data.timeline')->assertJsonPath('data.timeline.1.date_to', '2024-02-29')
            ->assertJsonPath('data.timeline.1.total', '12.34')->assertJsonPath('data.timeline.2.total', '45.67');
        $this->getJson($this->url(['period' => 'month', 'year' => 2024, 'month' => 2]))->assertOk()
            ->assertJsonCount(29, 'data.timeline')->assertJsonPath('data.summary.total_sales', '12.34')
            ->assertJsonPath('data.meta.previous_from', '2024-01-01')->assertJsonPath('data.meta.previous_to', '2024-01-31');
    }

    public function test_summary_uses_paid_orders_exact_money_and_separate_refunds(): void
    {
        $order = $this->sale('2026-10-19 01:00:00', '9.50', [
            'subtotal' => '10.00', 'discount_total' => '1.00', 'tax_total' => '0.50', 'supplemental_total' => '2.00',
        ], false);
        $cash = $this->payment($order, '4.00', '2026-10-19 01:00:00');
        $this->payment($order, '7.50', '2026-10-19 01:00:00', 'card');
        $this->refund($cash, '4.00', '2026-10-20 02:00:00');
        $missing = $this->sale('2026-10-19 01:00:00', '100.00', [], false);
        $pending = $this->payment($missing, '100.00', '2026-10-19 01:00:00');
        DB::table('payments')->where('id', $pending)->update(['status' => 'pending']);
        $this->sale('2026-10-19 01:00:00', '500.00', ['status' => 'held']);
        $this->getJson($this->url())->assertOk()
            ->assertJsonPath('data.summary.gross_sales', '10.00')
            ->assertJsonPath('data.summary.discounts', '1.00')->assertJsonPath('data.summary.tax', '0.50')
            ->assertJsonPath('data.summary.total_sales', '9.50')->assertJsonPath('data.summary.supplemental_sales', '2.00')
            ->assertJsonPath('data.summary.refunds', '4.00')->assertJsonPath('data.summary.net_sales', '7.50')
            ->assertJsonPath('data.summary.total_orders', 1)->assertJsonPath('data.summary.excluded_orders', 1)
            ->assertJsonPath('data.summary.payment_difference', '0.00')
            ->assertJsonPath('data.payment_methods.1.method', 'cash')->assertJsonPath('data.payment_methods.1.net', '0.00')
            ->assertJsonPath('data.cash_flow.refunds', '0.00');
        $this->getJson($this->url(['detail' => 'refunds']))->assertOk()->assertJsonPath('data.rows.0.order_id', $order);
        $this->getJson($this->url(['detail' => 'excluded']))->assertOk()->assertJsonPath('data.rows.0.order_id', $missing);
        $this->getJson($this->url(['period' => 'custom', 'date_from' => '2026-10-20', 'date_to' => '2026-10-20']))
            ->assertOk()->assertJsonPath('data.summary.refunds', '0.00')->assertJsonPath('data.cash_flow.refunds', '4.00');
        $this->getJson($this->url(['period' => 'custom', 'date_from' => '2026-10-20', 'date_to' => '2026-10-20', 'detail' => 'event_refunds']))
            ->assertOk()->assertJsonPath('data.total', 1)->assertJsonPath('data.rows.0.amount', '4.00')->assertJsonPath('data.rows.0.order_id', $order)
            ->assertJsonPath('data.rows.0.branch_name', $this->branch->name)
            ->assertJsonPath('data.rows.0.occurred_at_local', '2026-10-20 09:00:00 +07:00');
    }

    public function test_drawer_uses_whole_shift_and_old_sale_refunds_without_card_money(): void
    {
        $shift = DB::table('cashier_shifts')->insertGetId(['branch_id' => $this->branch->id,
            'user_id' => $this->manager->id, 'opening_cash' => '20.00', 'status' => 'closed',
            'expected_cash' => '27.00', 'counted_cash' => '26.50', 'closed_at' => '2026-10-19 10:00:00',
            'created_at' => '2026-10-18 16:00:00', 'updated_at' => '2026-10-19 10:00:00']);
        $oldOrder = $this->sale('2026-10-17 10:00:00', '5.00', [], false);
        $old = $this->payment($oldOrder, '5.00', '2026-10-17 10:00:00');
        $this->refund($old, '2.00', '2026-10-19 02:00:00', $shift);
        $new = $this->sale('2026-10-19 01:00:00', '110.00', [], false);
        $this->payment($new, '10.00', '2026-10-19 01:00:00', 'cash', $shift);
        $this->payment($new, '100.00', '2026-10-19 01:00:00', 'card', $shift);
        foreach ([['in', '3.00'], ['out', '4.00']] as [$type, $amount]) DB::table('cash_movements')->insert([
            'shift_id' => $shift, 'type' => $type, 'amount' => $amount, 'reason' => 'Float',
            'created_at' => '2026-10-19 02:00:00', 'updated_at' => '2026-10-19 02:00:00']);
        $this->getJson($this->url())->assertOk()->assertJsonPath('data.shifts.rows.0.expected', '27.00')
            ->assertJsonPath('data.shifts.rows.0.difference', '-0.50')->assertJsonPath('data.shifts.rows.0.cash_refunds', '2.00');
    }

    public function test_combined_report_uses_each_branch_timezone_and_retains_tenant_isolation(): void
    {
        $denver = Branch::factory()->create(['business_id' => $this->manager->business_id, 'timezone' => 'America/Denver']);
        $this->manager->branches()->attach($denver->id);
        $this->sale('2026-10-18 18:00:00', '1.00'); // October 19 in Phnom Penh
        $this->sale('2026-10-20 05:59:59', '2.00', ['branch_id' => $denver->id]); // October 19 Denver
        $this->sale('2026-10-20 06:00:00', '4.00', ['branch_id' => $denver->id]);
        $foreign = Branch::factory()->create();
        $this->sale('2026-10-19 01:00:00', '100.00', ['branch_id' => $foreign->id]);
        $url = '/api/v1/reports/sales?period=custom&date_from=2026-10-19&date_to=2026-10-19';
        $this->getJson($url)->assertOk()->assertJsonPath('data.summary.total_sales', '3.00');
        $this->getJson('/api/v1/reports/sales?branch_id='.$foreign->id)->assertForbidden();
        $this->getJson('/api/v1/reports/sales?branch_id='.$foreign->id.'&detail=orders')->assertForbidden();
    }

    public function test_filters_and_details_are_consistent_and_reject_foreign_identifiers(): void
    {
        $category = DB::table('categories')->insertGetId(['business_id' => $this->manager->business_id,
            'name' => 'Coffee', 'created_at' => now(), 'updated_at' => now()]);
        $product = DB::table('products')->insertGetId(['category_id' => $category, 'name' => 'Latte', 'base_price' => '10.00',
            'created_at' => now(), 'updated_at' => now()]);
        $order = $this->sale('2026-10-19 01:00:00');
        DB::table('order_items')->insert(['order_id' => $order, 'product_id' => $product, 'quantity' => 1,
            'unit_price' => '10.00', 'created_at' => now(), 'updated_at' => now()]);
        $this->sale('2026-10-19 01:00:00', '20.00');
        $filters = ['cashier_id' => $this->manager->id, 'category_id' => $category];
        $this->getJson($this->url($filters))->assertOk()->assertJsonPath('data.summary.total_orders', 1);
        $this->getJson($this->url($filters + ['detail' => 'orders']))->assertOk()->assertJsonPath('data.total', 1)
            ->assertJsonPath('data.rows.0.order_id', $order);
        $other = User::factory()->create();
        $this->getJson($this->url(['cashier_id' => $other->id]))->assertForbidden();
        $this->getJson($this->url(['category_id' => 99999]))->assertForbidden();
    }

    public function test_details_are_paginated_and_timeline_query_does_not_grow_per_bucket(): void
    {
        for ($i = 0; $i < 51; $i++) $this->sale('2026-10-19 01:00:00', '0.10');
        $this->getJson($this->url(['detail' => 'orders']))->assertOk()->assertJsonPath('data.total', 51)->assertJsonCount(50, 'data.rows');
        $this->getJson($this->url(['detail' => 'orders', 'page' => 2]))->assertOk()->assertJsonCount(1, 'data.rows');
        DB::enableQueryLog();
        $this->getJson($this->url(['period' => 'year', 'year' => 2026]))->assertOk()->assertJsonPath('data.summary.total_sales', '5.10');
        $queries = DB::getQueryLog(); DB::disableQueryLog();
        $this->assertCount(1, array_filter($queries, fn ($q) => str_contains($q['query'], 'bucket_0')));
        $this->getJson($this->url(['period' => 'custom', 'date_from' => '2020-01-01', 'date_to' => '2026-01-01']))->assertUnprocessable();
        $this->getJson($this->url(['period' => 'month', 'year' => 2026, 'month' => 13]))->assertUnprocessable();
    }

    public function test_source_amounts_match_the_selected_metric_and_dst_hours_keep_both_offsets(): void
    {
        $this->branch->update(['timezone' => 'America/Denver']);
        $id = $this->sale('2026-11-01 07:30:00', '9.50', ['subtotal' => '10.00', 'discount_total' => '1.00', 'tax_total' => '0.50']);
        $payment = DB::table('payments')->where('order_id', $id)->value('id');
        $this->refund($payment, '2.00', '2026-11-02 10:00:00');
        $this->sale('2026-11-01 08:30:00', '1.00');
        $range = ['period' => 'custom', 'date_from' => '2026-11-01', 'date_to' => '2026-11-01'];
        $data = $this->getJson($this->url($range))->assertOk()->assertJsonCount(25, 'data.hourly_sales')->json('data');
        $hours = collect($data['hourly_sales'])->keyBy('hour');
        $this->assertSame('9.50', $hours['01:00 -06:00']['total']);
        $this->assertSame('1.00', $hours['01:00 -07:00']['total']);
        $this->getJson($this->url($range + ['detail' => 'orders', 'metric' => 'discounts']))
            ->assertOk()->assertJsonPath('data.total', 1)->assertJsonPath('data.rows.0.amount', '1.00');
        $rows = $this->getJson($this->url($range + ['detail' => 'orders', 'metric' => 'net_sales']))
            ->assertOk()->json('data.rows');
        $this->assertSame(850, array_sum(array_map(fn ($r) => ReportMoney::cents($r['amount']), $rows)));
        $local = collect($rows)->keyBy('order_id');
        $this->assertSame('2026-11-01 01:30:00 -06:00', $local[$id]['occurred_at_local']);
    }

    public function test_month_to_date_comparison_caps_previous_month_and_permissions_are_required(): void
    {
        $this->travelTo(now('UTC')->setDate(2026, 3, 31)->setTime(10, 0));
        $this->getJson($this->url(['period' => 'this_month']))->assertOk()
            ->assertJsonPath('data.meta.previous_from', '2026-02-01')
            ->assertJsonPath('data.meta.previous_to', '2026-02-28');
        $this->getJson($this->url(['period' => 'month', 'year' => 2026, 'month' => 3]))->assertOk()
            ->assertJsonPath('data.meta.date_to', '2026-03-31')->assertJsonPath('data.meta.previous_to', '2026-02-28');
        $this->getJson($this->url(['period' => 'year', 'year' => 2026]))->assertOk()
            ->assertJsonPath('data.meta.date_to', '2026-03-31')->assertJsonPath('data.meta.previous_to', '2025-03-31')
            ->assertJsonCount(12, 'data.timeline')->assertJsonPath('data.timeline.3.upcoming', true);
        // Tuesday compares Monday/Tuesday of the preceding week, not the preceding weekend.
        $this->getJson($this->url(['period' => 'week']))->assertOk()
            ->assertJsonPath('data.meta.previous_from', '2026-03-23')->assertJsonPath('data.meta.previous_to', '2026-03-24');
        $this->manager->revokePermissionTo('reports.view');
        $this->getJson($this->url())->assertForbidden();
    }

    public function test_money_has_exact_rounding_and_defined_zero_comparisons(): void
    {
        $this->assertSame('90071992547409.91', ReportMoney::decimal(ReportMoney::cents('90071992547409.91')));
        $this->assertSame(101, ReportMoney::divide(201, 2));
        $this->assertNull(ReportMoney::comparison(100, 0)['percent']);
        $this->assertSame('new', ReportMoney::comparison(100, 0)['status']);
        $this->assertSame('-100.00', ReportMoney::comparison(0, 100)['percent']);
    }
}

