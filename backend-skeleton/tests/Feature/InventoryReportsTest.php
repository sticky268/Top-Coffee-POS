<?php

namespace Tests\Feature;

use App\Models\{Branch, Business, User, Unit, Ingredient, Product, Category, Order, OrderItem, RecipeItem};
use App\Services\SaleInventoryService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Spatie\Permission\Models\Permission;
use Tests\TestCase;

class InventoryReportsTest extends TestCase
{
    use RefreshDatabase;
    private Branch $branch;
    private User $user;
    private Ingredient $ingredient;
    private Product $product;
    protected function setUp(): void
    {
        parent::setUp();
        $this->travelTo(now()->setTimezone('UTC')->setDate(2026, 10, 19)->setTime(2, 0));
        $business = Business::factory()->create();
        $this->branch = Branch::factory()->create(['business_id' => $business->id, 'timezone' => 'Asia/Phnom_Penh']);
        $this->user = User::factory()->create(['business_id' => $business->id]);
        $this->user->branches()->attach($this->branch->id);
        $this->user->givePermissionTo(Permission::findOrCreate('reports.view'));
        $this->actingAs($this->user);
        $unit = Unit::create(['name' => 'Gram', 'abbreviation' => 'g']);
        $this->ingredient = Ingredient::create(['branch_id' => $this->branch->id, 'unit_id' => $unit->id, 'name' => 'Coffee', 'reorder_threshold' => '18.000', 'is_active' => true]);
        $category = Category::create(['business_id' => $business->id, 'name' => 'Drinks', 'is_active' => true]);
        $this->product = Product::create(['business_id' => $business->id, 'category_id' => $category->id, 'name' => 'Latte', 'base_price' => '10.00', 'is_active' => true]);
    }
    private function movement(string $quantity, ?string $cost = '2.000000', string $type = 'purchase', ?int $order = null, string $at = '2026-10-19 01:00:00', ?Ingredient $ingredient = null): int
    {
        $i = $ingredient ?? $this->ingredient;
        return DB::table('stock_movements')->insertGetId(['ingredient_id' => $i->id, 'branch_id' => $i->branch_id,
            'quantity' => $quantity, 'unit_cost' => $cost, 'balance_after' => '999.000', 'type' => $type,
            'reference_type' => $order ? (new Order)->getMorphClass() : null, 'reference_id' => $order,
            'created_by' => $this->user->id, 'reason' => 'Test ledger evidence', 'created_at' => $at, 'updated_at' => $at]);
    }
    private function sale(?string $expected = '2.000', bool $paid = true, ?User $user = null): int
    {
        $id = DB::table('orders')->insertGetId(['uuid' => (string) Str::uuid(), 'branch_id' => $this->branch->id,
            'user_id' => ($user ?? $this->user)->id, 'order_type' => 'takeaway', 'status' => 'completed', 'subtotal' => '10.00',
            'total' => '10.00', 'completed_at' => '2026-10-19 01:00:00', 'created_at' => '2026-10-19 01:00:00', 'updated_at' => '2026-10-19 01:00:00']);
        if ($paid) DB::table('payments')->insert(['order_id' => $id, 'amount' => '10.00', 'method' => 'cash', 'status' => 'completed', 'processed_by' => ($user ?? $this->user)->id]);
        DB::table('order_items')->insert(['order_id' => $id, 'product_id' => $this->product->id, 'product_name' => 'Latte', 'quantity' => 1, 'unit_price' => '10.00',
            'recipe_usage_snapshot' => $expected === null ? null : json_encode([['ingredient_id' => $this->ingredient->id, 'quantity' => $expected]])]);
        return $id;
    }
    private function report(array $input = [])
    {
        return $this->getJson('/api/v1/reports/sales?'.http_build_query($input + ['report' => 'inventory', 'branch_id' => $this->branch->id]));
    }
    public function test_ledger_valuation_usage_waste_and_comparisons_reconcile_without_using_caches(): void
    {
        $this->ingredient->forceFill(['current_stock' => '999.000', 'average_unit_cost' => '999.000000'])->save();
        $this->movement('10.000', '2.000000', at: '2026-10-18 01:00:00');
        $this->movement('10.000', '4.000000');
        $order = $this->sale();
        $this->movement('-3.000', '3.000000', 'sale_deduction', $order);
        $this->movement('1.000', '3.000000', 'sale_deduction', $order);
        $this->movement('-1.000', '3.000000', 'wastage');
        $this->movement('-2.000', '3.000000', 'adjustment');
        $data = $this->report()->assertOk()->assertJsonPath('data.summary.value', '45.000000')
            ->assertJsonPath('data.summary.comparisons.value.previous', '20.000000')
            ->assertJsonPath('data.summary.comparisons.value.percent', '125.00')
            ->assertJsonPath('data.summary.waste_cost', '3.000000')->assertJsonPath('data.summary.low_stock_items', 1)
            ->assertJsonPath('data.ingredients.0.opening', '10.000')->assertJsonPath('data.ingredients.0.closing', '15.000')
            ->assertJsonPath('data.ingredients.0.expected', '2.000')->assertJsonPath('data.ingredients.0.deducted', '3.000')
            ->assertJsonPath('data.ingredients.0.variance', '1.000')->assertJsonPath('data.ingredients.0.returned', '1.000')->json('data');
        $this->assertArrayNotHasKey('quantity', $data['summary']); // Units cannot be added across ingredients.
        $this->report(['detail' => 'inventory', 'ingredient_id' => $this->ingredient->id, 'inventory_kind' => 'sales'])
            ->assertOk()->assertJsonCount(1, 'data.rows')->assertJsonPath('data.rows.0.order_id', $order)->assertJsonPath('data.rows.0.expected', '2.000');
        $this->report(['detail' => 'inventory', 'ingredient_id' => $this->ingredient->id, 'inventory_kind' => 'waste'])
            ->assertOk()->assertJsonCount(1, 'data.rows')->assertJsonPath('data.rows.0.quantity', '-1.000');
    }
    public function test_refund_waste_reclassification_does_not_revalue_remaining_stock(): void
    {
        $this->movement('11.000', '2.000000', at: '2026-10-18 01:00:00');
        $this->movement('-1.000', '2.000000', 'sale_deduction', at: '2026-10-18 02:00:00');
        $this->movement('10.000', '6.000000');
        $this->movement('1.000', '2.000000', 'sale_deduction');
        $this->movement('-1.000', '2.000000', 'wastage');
        $this->report()->assertOk()->assertJsonPath('data.summary.value', '80.000000')
            ->assertJsonPath('data.summary.waste_cost', '2.000000')->assertJsonPath('data.ingredients.0.closing', '20.000');
    }
    public function test_unknown_cost_and_legacy_recipe_history_are_unavailable_not_zero(): void
    {
        $this->movement('10.000', null, at: '2026-10-18 01:00:00');
        $order = $this->sale(null);
        $this->movement('-1.000', '50.000000', 'sale_deduction', $order);
        $this->movement('-1.000', null, 'wastage');
        $this->report()->assertOk()->assertJsonPath('data.summary.value', null)->assertJsonPath('data.summary.known_value', '0.000000')
            ->assertJsonPath('data.summary.unknown_value_items', 1)->assertJsonPath('data.summary.waste_cost', null)
            ->assertJsonPath('data.summary.missing_recipe_lines', 1)->assertJsonPath('data.summary.variance_items', null)
            ->assertJsonPath('data.ingredients.0.expected', null)->assertJsonPath('data.ingredients.0.variance', null);
    }
    public function test_unknown_pool_becomes_known_only_after_exhaustion_and_costs_keep_six_decimals(): void
    {
        $this->movement('1.000', null, at: '2026-10-18 01:00:00');
        $this->movement('-1.000', null, 'adjustment');
        $this->movement('2.000', '1.000001');
        $this->movement('-0.001', '1.000001', 'wastage');
        $this->report()->assertOk()->assertJsonPath('data.summary.value', '1.999002')
            ->assertJsonPath('data.summary.waste_cost', '0.001000')->assertJsonPath('data.summary.unknown_value_items', 0);
    }
    public function test_usage_filters_do_not_falsely_filter_branch_stock_and_unpaid_sales_are_excluded(): void
    {
        $this->movement('20.000');
        $mine = $this->sale(); $this->movement('-2.000', '2.000000', 'sale_deduction', $mine);
        $other = User::factory()->create(['business_id' => $this->user->business_id]); $other->branches()->attach($this->branch->id);
        $theirs = $this->sale('3.000', user: $other); $this->movement('-3.000', '2.000000', 'sale_deduction', $theirs);
        $unpaid = $this->sale(null, false); $this->movement('-1.000', '2.000000', 'sale_deduction', $unpaid);
        $this->movement('-1.000', '2.000000', 'wastage');
        $this->report(['cashier_id' => $this->user->id, 'category_id' => $this->product->category_id])->assertOk()
            ->assertJsonPath('data.summary.sales', 1)->assertJsonPath('data.summary.missing_recipe_lines', 0)
            ->assertJsonPath('data.summary.value', '26.000000')->assertJsonPath('data.summary.waste_cost', '2.000000')
            ->assertJsonPath('data.ingredients.0.expected', '2.000')->assertJsonPath('data.ingredients.0.deducted', '2.000');
    }
    public function test_branch_timezone_dst_boundaries_and_future_returns_are_respected(): void
    {
        $this->branch->update(['timezone' => 'America/New_York']);
        $this->movement('1.000', at: '2026-11-01 03:59:59'); // Opening, local Oct31.
        $this->movement('1.000', at: '2026-11-01 05:30:00');
        $this->movement('1.000', at: '2026-11-01 06:30:00'); // Repeated hour.
        $this->movement('1.000', at: '2026-11-02 04:59:59');
        $this->movement('99.000', at: '2026-11-02 05:00:00'); // Exact end excluded.
        $this->report(['period' => 'custom', 'date_from' => '2026-11-01', 'date_to' => '2026-11-01'])->assertOk()
            ->assertJsonPath('data.ingredients.0.opening', '1.000')->assertJsonPath('data.ingredients.0.closing', '4.000');
        $order = $this->sale(); $this->movement('-1.000', type: 'sale_deduction', order: $order);
        $this->movement('1.000', type: 'sale_deduction', order: $order, at: '2026-10-20 12:00:00');
        $this->report()->assertOk()->assertJsonPath('data.ingredients.0.returned', '0.000');
    }
    public function test_source_permissions_validation_archives_and_pagination(): void
    {
        for ($j = 0; $j < 51; $j++) $this->movement('0.001');
        $this->report(['detail' => 'inventory', 'ingredient_id' => $this->ingredient->id, 'page' => 2])->assertOk()
            ->assertJsonPath('data.total', 51)->assertJsonCount(1, 'data.rows');
        $this->ingredient->delete();
        $this->report()->assertOk()->assertJsonPath('data.summary.low_stock_items', 0)->assertJsonPath('data.ingredients.0.active', false);
        $foreignBranch = Branch::factory()->create();
        $foreign = Ingredient::create(['branch_id' => $foreignBranch->id, 'unit_id' => $this->ingredient->unit_id, 'name' => 'Private ingredient']);
        $this->report(['detail' => 'inventory', 'ingredient_id' => $foreign->id])->assertForbidden();
        $this->report(['branch_id' => $foreignBranch->id])->assertForbidden();
        $this->report(['detail' => 'inventory'])->assertUnprocessable();
        $this->report(['inventory_kind' => 'invalid'])->assertUnprocessable();
        $this->getJson('/api/v1/reports/sales?detail=inventory&ingredient_id='.$this->ingredient->id)->assertUnprocessable();
        $this->user->revokePermissionTo('reports.view'); $this->report()->assertForbidden();
    }
    public function test_completion_captures_recipe_quantities_and_recipe_edits_do_not_rewrite_history(): void
    {
        $this->ingredient->forceFill(['current_stock' => '10.000', 'average_unit_cost' => '2.000000'])->save();
        $this->movement('10.000', at: '2026-10-18 01:00:00');
        $order = $this->sale(null); $item = OrderItem::where('order_id', $order)->first(); $item->update(['quantity' => 2]);
        $recipe = RecipeItem::create(['branch_id' => $this->branch->id, 'product_id' => $this->product->id, 'ingredient_id' => $this->ingredient->id, 'quantity_used' => '1.001']);
        DB::transaction(fn () => app(SaleInventoryService::class)->deductForOrder(Order::findOrFail($order), $this->user->id));
        $this->assertSame('2.002', $item->fresh()->recipe_usage_snapshot[0]['quantity']);
        $recipe->update(['quantity_used' => '9.000']);
        $this->report()->assertOk()->assertJsonPath('data.ingredients.0.expected', '2.002')->assertJsonPath('data.ingredients.0.variance', '0.000');
    }
    public function test_snapshot_and_ledger_rollback_together_when_completion_fails(): void
    {
        $this->ingredient->forceFill(['current_stock' => '10.000', 'average_unit_cost' => '2.000000'])->save();
        $order = $this->sale(null);
        RecipeItem::create(['branch_id' => $this->branch->id, 'product_id' => $this->product->id, 'ingredient_id' => $this->ingredient->id, 'quantity_used' => '1.000']);
        $before = DB::table('stock_movements')->count();
        try {
            DB::transaction(function () use ($order) { app(SaleInventoryService::class)->deductForOrder(Order::findOrFail($order), $this->user->id); throw new \RuntimeException('Simulated completion failure'); });
        } catch (\RuntimeException $e) { $this->assertSame('Simulated completion failure', $e->getMessage()); }
        $this->assertNull(OrderItem::where('order_id', $order)->first()->recipe_usage_snapshot);
        $this->assertSame($before, DB::table('stock_movements')->count());
        $this->assertSame('10.000', $this->ingredient->fresh()->current_stock);
    }
}
