<?php

namespace Tests\Feature;

use App\Models\{Branch, Business, Category, Product, User, Order, OrderItem, RecipeItem, Unit, Ingredient, ProductVariant, Modifier, ModifierGroup, OrderItemModifier};
use App\Services\{SaleInventoryService, StockMovementService};
use App\Services\Reports\ReportAllocation;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Spatie\Permission\Models\Permission;
use Tests\TestCase;

class ProfitReportsTest extends TestCase
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
        return $this->getJson('/api/v1/reports/sales?'.http_build_query($filters + ['branch_id' => $this->branch->id, 'report' => 'profit']));
    }

    private function refund(int $order, string $amount, string $disposition = 'consumed'): void
    {
        $payment = DB::table('payments')->where('order_id', $order)->value('id');
        DB::table('payments')->where('id', $payment)->update(['status' => 'partially_refunded']);
        DB::table('payment_refunds')->insert(['payment_id' => $payment, 'amount' => $amount,
            'reason' => 'Correction', 'inventory_disposition' => $disposition, 'processed_by' => $this->actor->id,
            'created_at' => '2026-10-20 01:00:00', 'updated_at' => '2026-10-20 01:00:00']);
    }

    public function test_exact_allocations_reconcile_tax_discount_refunds_and_all_groupings(): void
    {
        $order = $this->sale(['subtotal' => '10.00', 'discount_total' => '1.00', 'tax_total' => '0.90', 'total' => '9.90']);
        // Original payment deliberately includes a 0.10 overcollection: never revenue.
        $this->item($order, '0.123456', ['unit_price' => '3.33']);
        $this->item($order, '1.000001', ['product_id' => $this->product('Tea')->id, 'product_name' => 'Tea', 'unit_price' => '6.67']);
        $this->refund($order, '3.30');
        $report = $this->report()->assertOk()->assertJsonPath('data.summary.revenue', '6.00')
            ->assertJsonPath('data.summary.refunds', '3.00')->assertJsonPath('data.summary.refund_tax', '0.30')
            ->assertJsonPath('data.summary.cogs', '1.123457')->assertJsonPath('data.summary.gross_profit', '4.876543');
        foreach (['products', 'categories', 'branches'] as $group) {
            $rows = $report->json('data.'.$group);
            $this->assertSame(600, array_sum(array_map(fn ($r) => \App\Services\Reports\ReportMoney::cents($r['revenue']), $rows)));
            $this->assertSame(1123457, array_sum(array_map(fn ($r) => ReportAllocation::micros($r['cogs']), $rows)));
        }
        $this->report(['detail' => 'profit'])->assertOk()->assertJsonCount(2, 'data.rows')
            ->assertJsonPath('data.rows.0.branch_name', $this->branch->name)
            ->assertJsonPath('data.rows.0.occurred_at_local', '2026-10-19 08:00:00 +07:00');
    }

    public function test_old_categories_and_unknown_costs_are_never_repriced_or_zero_filled(): void
    {
        $order = $this->sale();
        $this->item($order, null, ['sale_category_captured' => false, 'sale_category_id' => null]);
        $this->product->update(['base_price' => '99.00', 'name' => 'Changed product']);
        $this->category->update(['name' => 'Changed category']);
        $this->report()->assertOk()->assertJsonPath('data.summary.cogs', null)
            ->assertJsonPath('data.summary.gross_profit', null)->assertJsonPath('data.summary.margin_percent', null)
            ->assertJsonPath('data.summary.unknown_cost_lines', 1)->assertJsonPath('data.summary.known_cogs', '0.000000')
            ->assertJsonPath('data.categories.0.id', 'legacy')->assertJsonPath('data.products.0.name', 'Latte');
        $this->report(['category_id' => $this->category->id])->assertOk()->assertJsonPath('data.summary.revenue', '0.00');
        $this->report(['detail' => 'profit', 'profit_category' => 'legacy'])->assertOk()->assertJsonCount(1, 'data.rows');
    }

    public function test_paid_selection_and_branch_local_boundaries_and_previous_comparisons(): void
    {
        $this->item($this->sale([], '2026-10-18 16:59:59'), '1.000001');
        $this->item($this->sale([], '2026-10-18 17:00:00'), '2.000002');
        $this->item($this->sale([], '2026-10-19 01:00:00', false), '9.000000');
        $this->report()->assertOk()->assertJsonPath('data.summary.revenue', '10.00')
            ->assertJsonPath('data.summary.cogs', '2.000002')->assertJsonPath('data.summary.comparisons.cogs.percent', '100.00')
            ->assertJsonPath('data.summary.comparisons.cogs.previous', '1.000001');
        $other = Branch::factory()->create();
        $this->report(['branch_id' => $other->id])->assertForbidden();
        $this->actor->revokePermissionTo('reports.view');
        $this->report()->assertForbidden();
    }

    public function test_full_restock_requires_balanced_ledger_and_waste_retains_cost(): void
    {
        $unit = Unit::create(['name' => 'Kilogram', 'abbreviation' => 'kg', 'conversion_factor' => 1]);
        $ingredient = Ingredient::create(['branch_id' => $this->branch->id, 'unit_id' => $unit->id, 'name' => 'Beans', 'is_active' => true]);
        $order = $this->sale(['inventory_disposed_at' => now()]);
        $this->item($order);
        $this->refund($order, '10.00', 'restock');
        $this->report()->assertOk()->assertJsonPath('data.summary.cogs', null);
        foreach (['-1.000', '1.000'] as $quantity) DB::table('stock_movements')->insert([
            'ingredient_id' => $ingredient->id, 'branch_id' => $this->branch->id, 'type' => 'sale_deduction',
            'quantity' => $quantity, 'balance_after' => 0, 'unit_cost' => '2.000000', 'created_by' => $this->actor->id,
            'reference_type' => (new Order)->getMorphClass(), 'reference_id' => $order]);
        $this->report()->assertOk()->assertJsonPath('data.summary.revenue', '0.00')
            ->assertJsonPath('data.summary.cogs', '0.000000')->assertJsonPath('data.summary.reversed_cogs', '2.000000');
        DB::table('payment_refunds')->update(['inventory_disposition' => 'wastage']);
        $this->report()->assertOk()->assertJsonPath('data.summary.cogs', '2.000000')->assertJsonPath('data.summary.gross_profit', '-2.000000');
    }

    public function test_rankings_include_slow_zero_and_disappeared_sellers_with_missing_cost_flags(): void
    {
        $this->item($this->sale(), '2.000000', ['quantity' => 3]);
        $tea = $this->product('Tea');
        $this->item($this->sale(), null, ['product_id' => $tea->id, 'product_name' => 'Tea']);
        $zero = $this->product('Unsold');
        $previous = $this->product('Previous only');
        $this->item($this->sale([], '2026-10-18 01:00:00'), '1.000000', ['product_id' => $previous->id, 'product_name' => 'Previous only']);
        $r = $this->report()->assertOk()->assertJsonPath('data.best_sellers.0.id', $this->product->id)
            ->assertJsonPath('data.slow_sellers.0.id', $tea->id)->assertJsonCount(2, 'data.unsold_products');
        $products = collect($r->json('data.products'))->keyBy('id');
        $this->assertSame('cost_missing', $products[$tea->id]['performance']);
        $this->assertSame('no_sales', $products[$previous->id]['performance']);
        $this->assertSame('-100.00', $products[$previous->id]['comparisons']['revenue']['percent']);
    }


    public function test_completed_sale_snapshots_variant_modifier_cost_and_category_before_recipe_changes(): void
    {
        $unit = Unit::create(['name' => 'Kilogram', 'abbreviation' => 'kg', 'conversion_factor' => 1]);
        $ingredient = Ingredient::create(['branch_id' => $this->branch->id, 'unit_id' => $unit->id, 'name' => 'Beans', 'is_active' => true]);
        app(StockMovementService::class)->record($ingredient, 'purchase', 5, $this->actor->id, null, null, 10);
        $variant = ProductVariant::create(['product_id' => $this->product->id, 'name' => 'Large', 'price_delta' => 0, 'recipe_multiplier' => 2, 'is_active' => true]);
        $group = ModifierGroup::create(['name' => 'Extras']);
        $modifier = Modifier::create(['modifier_group_id' => $group->id, 'name' => 'Extra beans', 'price_delta' => 0, 'is_active' => true]);
        RecipeItem::create(['branch_id' => $this->branch->id, 'product_id' => $this->product->id, 'ingredient_id' => $ingredient->id, 'quantity_used' => '0.100']);
        RecipeItem::create(['branch_id' => $this->branch->id, 'modifier_id' => $modifier->id, 'ingredient_id' => $ingredient->id, 'quantity_used' => '0.050']);
        $order = $this->sale();
        $item = $this->item($order, null, ['product_variant_id' => $variant->id, 'quantity' => 2, 'sale_category_captured' => false]);
        OrderItemModifier::create(['order_item_id' => $item, 'modifier_id' => $modifier->id, 'price_delta' => 0]);
        DB::transaction(fn () => app(SaleInventoryService::class)->deductForOrder(Order::findOrFail($order), $this->actor->id));
        $this->assertDatabaseHas('order_items', ['id' => $item, 'sale_category_captured' => true, 'sale_category_name' => 'Coffee', 'ingredient_cost' => '5.000000']);
        RecipeItem::query()->update(['quantity_used' => '0.900']);
        $ingredient->update(['average_unit_cost' => '99.000000']);
        $this->category->update(['name' => 'Changed']);
        $this->report()->assertOk()->assertJsonPath('data.summary.cogs', '5.000000')
            ->assertJsonPath('data.categories.0.name', 'Coffee')->assertJsonPath('data.summary.gross_profit', '5.000000');
    }

    public function test_details_paginate_and_filters_attribute_only_selected_items(): void
    {
        $otherCategory = Category::create(['name' => 'Food', 'is_active' => true]);
        $other = $this->product('Toast');
        $order = $this->sale();
        $this->item($order, '1.000000', ['unit_price' => '5.00']);
        $this->item($order, '1.000000', ['product_id' => $other->id, 'product_name' => 'Toast', 'unit_price' => '5.00', 'sale_category_id' => $otherCategory->id, 'sale_category_name' => 'Food']);
        $this->report(['category_id' => $this->category->id])->assertOk()->assertJsonPath('data.summary.revenue', '5.00')->assertJsonCount(1, 'data.products');
        for ($i = 0; $i < 51; $i++) $this->item($this->sale());
        $this->report(['detail' => 'profit', 'product_id' => $this->product->id, 'page' => 2])->assertOk()
            ->assertJsonPath('data.total', 52)->assertJsonCount(2, 'data.rows');
        $this->report(['cashier_id' => User::factory()->create()->id])->assertForbidden();
    }

    public function test_allocation_handles_ties_subcent_costs_and_large_values_without_floats(): void
    {
        $this->assertSame([1, 1, 0], ReportAllocation::split(2, [1, 1, 1]));
        $this->assertSame([-1, -1, 0], ReportAllocation::split(-2, [1, 1, 1]));
        $this->assertSame([1, 0], ReportAllocation::split(1, [0, 0]));
        $this->assertSame([999999999999, 0], ReportAllocation::quotient(999999999999, 999999999999, 999999999999));
        $this->assertSame(-2, ReportAllocation::ratio(-1, 3, 2));
        $this->assertSame('0.000001', ReportAllocation::decimal(ReportAllocation::micros('0.000001')));
    }
}
