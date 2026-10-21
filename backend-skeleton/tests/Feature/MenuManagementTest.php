<?php

namespace Tests\Feature;

use App\Models\{Branch, Business, User, Product, Category, Unit, Ingredient, RecipeItem, Order, OrderItem, ModifierGroup};
use App\Services\{MenuSaleService, SaleInventoryService, StockMovementService};
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Spatie\Permission\Models\Permission;
use Tests\TestCase;

class MenuManagementTest extends TestCase
{
    use RefreshDatabase;
    private Branch $branch;
    private User $user;
    private Product $product;

    protected function setUp(): void
    {
        parent::setUp();
        $business = Business::factory()->create();
        $this->branch = Branch::factory()->create(['business_id' => $business->id, 'timezone' => 'Asia/Phnom_Penh']);
        $this->user = User::factory()->create(['business_id' => $business->id]);
        $this->user->branches()->attach($this->branch->id, ['is_primary' => true]);
        foreach (['products.manage', 'orders.create', 'orders.edit', 'orders.view', 'reports.view'] as $permission) $this->user->givePermissionTo(Permission::findOrCreate($permission));
        $this->actingAs($this->user);
        $category = Category::create(['name' => 'Coffee']);
        $this->product = Product::create(['name' => 'Latte', 'category_id' => $category->id, 'base_price' => '3.25', 'is_active' => true]);
        $this->product->branches()->attach($this->branch->id, ['is_available' => true, 'price_override' => '3.75']);
    }

    private function combo(): array
    {
        return ['branch_id' => $this->branch->id, 'name' => 'Two coffees', 'category_id' => $this->product->category_id,
            'base_price' => '5.99', 'is_active' => true, 'combo_slots' => [
                ['name' => 'Coffee', 'quantity' => 2, 'choices' => [['product_id' => $this->product->id, 'extra_price' => '0.10']]],
            ]];
    }

    public function test_management_preserves_base_prices_and_includes_archived_items(): void
    {
        $this->product->update(['is_active' => false]);
        $this->getJson('/api/v1/menu?branch_id='.$this->branch->id)->assertOk()
            ->assertJsonPath('data.products.0.base_price', '3.25')->assertJsonPath('data.products.0.is_active', false)
            ->assertJsonPath('data.products.0.branches.0.pivot.price_override', 3.75);
    }

    public function test_combo_and_modifiers_are_priced_by_server_and_deduct_components_atomically(): void
    {
        $unit = Unit::create(['name' => 'Gram', 'abbreviation' => 'g']);
        $ingredient = Ingredient::create(['branch_id' => $this->branch->id, 'unit_id' => $unit->id, 'name' => 'Coffee beans', 'reorder_threshold' => 1, 'is_active' => true]);
        app(StockMovementService::class)->record($ingredient, 'purchase', 100, $this->user->id, 'Opening test stock', null, '0.05');
        RecipeItem::create(['branch_id' => $this->branch->id, 'product_id' => $this->product->id, 'ingredient_id' => $ingredient->id, 'quantity_used' => 5]);
        $comboId = $this->postJson('/api/v1/menu/combos', $this->combo())->assertCreated()->json('data.id');
        $order = $this->postJson('/api/v1/orders', ['branch_id' => $this->branch->id, 'order_type' => 'takeaway',
            'items' => [['product_id' => $comboId, 'quantity' => 3, 'combo_selections' => [$this->product->id]]],
            'payment' => ['method' => 'cash', 'tendered' => 20], 'expected_total' => '18.27',
        ])->assertCreated()->assertJsonPath('data.total', 18.27)->json('data.id');
        $line = OrderItem::where('order_id', $order)->firstOrFail();
        $this->assertSame('18.27', Order::find($order)->total);
        $this->assertSame('1.500000', number_format((float) $line->ingredient_cost, 6, '.', ''));
        $this->assertEquals(-30, DB::table('stock_movements')->where('reference_id', $order)->where('type', 'sale_deduction')->sum('quantity'));
        $this->getJson('/api/v1/orders/'.$order)->assertOk()->assertJsonPath('data.items.0.menu_configuration.components.0.quantity', 2);
        DB::transaction(fn () => app(SaleInventoryService::class)->reverseForOrder(Order::find($order), $this->user->id));
        $this->assertEquals(0, DB::table('stock_movements')->where('reference_id', $order)->where('type', 'sale_deduction')->sum('quantity'));
    }

    public function test_required_modifiers_and_foreign_options_are_rejected_before_order_creation(): void
    {
        $group = ModifierGroup::create(['name' => 'Milk', 'min_select' => 1, 'max_select' => 1, 'is_required' => true]);
        $option = $group->modifiers()->create(['name' => 'Oat', 'price_delta' => '0.45', 'is_active' => true]);
        $group->products()->attach($this->product->id);
        $payload = ['order_type' => 'takeaway', 'branch_id' => $this->branch->id, 'items' => [['product_id' => $this->product->id, 'quantity' => 1]], 'payment' => ['method' => 'cash']];
        $this->postJson('/api/v1/orders', $payload)->assertUnprocessable();
        $this->assertDatabaseCount('orders', 0);
        $payload['items'][0]['modifier_ids'] = [$option->id];
        $this->postJson('/api/v1/orders', $payload)->assertCreated()->assertJsonPath('data.total', 4.2);
        $payload['items'][0]['modifier_ids'] = [$option->id, $option->id];
        $this->postJson('/api/v1/orders', $payload)->assertUnprocessable();
        $this->assertDatabaseCount('orders', 1);
    }

    public function test_discounts_enforce_schedule_branch_scope_and_exact_percentage_rounding(): void
    {
        $this->travelTo(now('UTC')->setDate(2026, 10, 21)->setTime(18, 0)); // Oct 22 in branch.
        $discount = $this->postJson('/api/v1/menu/discounts', ['branch_id' => $this->branch->id, 'name' => 'Offer', 'type' => 'percent', 'value' => '12.50', 'is_active' => true, 'requires_manager' => false, 'all_branches' => false, 'starts_on' => '2026-10-22', 'ends_on' => '2026-10-22'])->assertOk()->json('data.id');
        $this->assertSame(47, app(MenuSaleService::class)->discount($discount, 375, $this->branch->id, 0));
        $this->getJson('/api/v1/menu/discounts?branch_id='.$this->branch->id)->assertOk()->assertJsonCount(1, 'data');
        $this->travelTo(now()->addDays(2));
        $this->getJson('/api/v1/menu/discounts?branch_id='.$this->branch->id)->assertOk()->assertJsonCount(0, 'data');
    }

    public function test_tenant_and_permission_boundaries_and_invalid_combo_cycles(): void
    {
        $foreign = Branch::factory()->create();
        $this->getJson('/api/v1/menu?branch_id='.$foreign->id)->assertForbidden();
        $id = $this->postJson('/api/v1/menu/combos', $this->combo())->assertCreated()->json('data.id');
        $payload = $this->combo();
        $payload['combo_slots'][0]['choices'][0]['product_id'] = $id;
        $this->postJson('/api/v1/menu/combos', $payload)->assertUnprocessable();
        $this->user->revokePermissionTo('products.manage');
        $this->getJson('/api/v1/menu?branch_id='.$this->branch->id)->assertForbidden();
        $this->postJson('/api/v1/menu/combos', $this->combo())->assertForbidden();
    }
}
