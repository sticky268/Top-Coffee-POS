<?php

namespace Tests\Feature;

use App\Models\{Branch, Business, User, Order, Payment, Ingredient, Unit, Product, Category, OrderItem, RecipeItem, ProductVariant};
use App\Services\{StockMovementService, SaleInventoryService};
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Spatie\Permission\Models\Permission;
use Tests\TestCase;

class CafeOperationsTest extends TestCase
{
    use RefreshDatabase;
    private User $actor;
    private Branch $branch;

    protected function setUp(): void
    {
        parent::setUp();
        $business = Business::factory()->create();
        $this->branch = Branch::create(['business_id' => $business->id, 'name' => 'Cafe', 'code' => 'OP-01', 'timezone' => 'Asia/Phnom_Penh']);
        $this->actor = User::factory()->create(['business_id' => $business->id]);
        $this->actor->branches()->attach($this->branch->id);
        foreach (['orders.create', 'orders.view', 'orders.refund', 'inventory.view', 'inventory.adjust', 'reports.view'] as $name) {
            Permission::firstOrCreate(['name' => $name, 'guard_name' => 'web']);
            $this->actor->givePermissionTo($name);
        }
        $this->actingAs($this->actor);
    }

    private function payload(array $data = []): array
    {
        return $data + ['uuid' => (string) Str::uuid(), 'branch_id' => $this->branch->id];
    }

    private function open(float $cash = 20): int
    {
        return $this->postJson('/api/v1/shifts', $this->payload(['opening_cash' => $cash]))->assertCreated()->json('data.id');
    }

    private function order(float $amount = 10, string $method = 'cash'): Order
    {
        $order = Order::create(['uuid' => (string) Str::uuid(), 'branch_id' => $this->branch->id, 'user_id' => $this->actor->id, 'order_type' => 'takeaway', 'status' => 'completed', 'subtotal' => $amount, 'total' => $amount, 'completed_at' => now()]);
        Payment::create(['order_id' => $order->id, 'method' => $method, 'amount' => $amount, 'status' => 'completed', 'processed_by' => $this->actor->id]);
        return $order;
    }

    private function ingredient(string $name = 'Coffee', ?Branch $branch = null, string $unit = 'kg'): Ingredient
    {
        $u = Unit::firstOrCreate(['abbreviation' => $unit], ['name' => $unit, 'conversion_factor' => $unit === 'kg' ? 1000 : 1]);
        return Ingredient::create(['branch_id' => ($branch ?? $this->branch)->id, 'unit_id' => $u->id, 'name' => $name, 'reorder_threshold' => 1, 'is_active' => true]);
    }

    public function test_open_is_idempotent_and_conflicting_payload_is_rejected(): void
    {
        $input = $this->payload(['opening_cash' => 20]);
        $id = $this->postJson('/api/v1/shifts', $input)->assertCreated()->json('data.id');
        $this->postJson('/api/v1/shifts', $input)->assertCreated()->assertJsonPath('data.id', $id);
        $this->postJson('/api/v1/shifts', array_replace($input, ['opening_cash' => 30]))->assertConflict();
        $this->postJson('/api/v1/shifts', $this->payload(['opening_cash' => 0]))->assertConflict();
        $this->assertDatabaseCount('cashier_shifts', 1);
    }

    public function test_shift_tracks_net_cash_and_requires_difference_reason(): void
    {
        $id = $this->open();
        $order = $this->order();
        $this->postJson("/api/v1/orders/{$order->id}/refund", $this->payload(['amount' => 3, 'reason' => 'Goodwill', 'inventory_disposition' => 'consumed']))->assertOk();
        $this->postJson("/api/v1/shifts/$id/movements", $this->payload(['type' => 'out', 'amount' => 2, 'reason' => 'Petty cash']))->assertOk()->assertJsonPath('data.live_expected_cash', 25);
        $this->postJson("/api/v1/shifts/$id/close", $this->payload(['counted_cash' => 24]))->assertUnprocessable();
        $input = $this->payload(['counted_cash' => 24, 'reason' => 'Short by one dollar']);
        $this->postJson("/api/v1/shifts/$id/close", $input)->assertOk()->assertJsonPath('data.difference', '-1.00');
        $this->postJson("/api/v1/shifts/$id/close", $input)->assertOk();
        $this->postJson("/api/v1/shifts/$id/movements", $this->payload(['type' => 'in', 'amount' => 1, 'reason' => 'Too late']))->assertConflict();
        $this->postJson("/api/v1/shifts/$id/review", $this->payload())->assertOk();
    }

    public function test_retries_do_not_refund_twice_and_over_refund_is_rejected(): void
    {
        $this->open();
        $order = $this->order();
        $input = $this->payload(['amount' => 4, 'reason' => 'Correction', 'inventory_disposition' => 'consumed']);
        $this->postJson("/api/v1/orders/{$order->id}/refund", $input)->assertOk()->assertJsonPath('data.net_paid', 6);
        $this->postJson("/api/v1/orders/{$order->id}/refund", $input)->assertOk()->assertJsonPath('data.net_paid', 6);
        $this->assertDatabaseCount('payment_refunds', 1);
        $this->postJson("/api/v1/orders/{$order->id}/refund", $this->payload(['amount' => 7, 'reason' => 'Too much', 'inventory_disposition' => 'consumed']))->assertUnprocessable();
        $this->assertDatabaseHas('payments', ['order_id' => $order->id, 'amount' => 10, 'status' => 'partially_refunded']);
    }

    public function test_consumed_refund_keeps_inventory_and_full_restock_reverses_it_once(): void
    {
        $this->open();
        $order = $this->order();
        $ingredient = $this->ingredient();
        $stock = app(StockMovementService::class);
        $stock->record($ingredient, 'purchase', 2, $this->actor->id, 'Opening stock', null, 10);
        $stock->record($ingredient, 'sale_deduction', -0.2, $this->actor->id, 'Sale', $order);
        $input = $this->payload(['amount' => 10, 'reason' => 'Not prepared', 'inventory_disposition' => 'restock']);
        $this->postJson("/api/v1/orders/{$order->id}/refund", $input)->assertOk();
        $this->postJson("/api/v1/orders/{$order->id}/refund", $input)->assertOk();
        $this->assertEquals(2, $ingredient->fresh()->current_stock);
    }

    public function test_wastage_refund_reclassifies_consumption_without_restoring_stock(): void
    {
        $this->open(); $order = $this->order(); $ingredient = $this->ingredient();
        $stock = app(StockMovementService::class);
        $stock->record($ingredient, 'purchase', 2, $this->actor->id, 'Opening', null, 10);
        $stock->record($ingredient, 'sale_deduction', -0.2, $this->actor->id, 'Sale', $order);
        $this->postJson("/api/v1/orders/{$order->id}/refund", $this->payload(['amount' => 10, 'reason' => 'Discarded drink', 'inventory_disposition' => 'wastage']))->assertOk();
        $this->assertEquals(1.8, $ingredient->fresh()->current_stock);
        $this->assertDatabaseHas('stock_movements', ['ingredient_id' => $ingredient->id, 'type' => 'wastage', 'quantity' => -0.2]);
    }

    public function test_partial_refund_cannot_restock_and_cash_refund_requires_open_shift(): void
    {
        $order = $this->order();
        $this->postJson("/api/v1/orders/{$order->id}/refund", $this->payload(['amount' => 2, 'reason' => 'Partial', 'inventory_disposition' => 'restock']))->assertUnprocessable();
        $this->postJson("/api/v1/orders/{$order->id}/refund", $this->payload(['amount' => 2, 'reason' => 'Partial', 'inventory_disposition' => 'consumed']))->assertConflict();
        $this->assertDatabaseCount('payment_refunds', 0);
    }

    public function test_additional_charge_preserves_original_payment_and_replays(): void
    {
        $this->open(); $order = $this->order();
        $input = $this->payload(['amount' => 2, 'method' => 'cash', 'tendered' => 5, 'reason' => 'Service correction']);
        $this->postJson("/api/v1/orders/{$order->id}/additional-charge", $input)->assertOk()->assertJsonPath('data.paid', 12);
        $this->postJson("/api/v1/orders/{$order->id}/additional-charge", $input)->assertOk();
        $this->assertDatabaseCount('payments', 2);
        $this->assertDatabaseHas('payments', ['order_id' => $order->id, 'amount' => 10]);
        $this->assertEquals(10, $order->fresh()->total);
        $this->assertEquals(2, $order->fresh()->supplemental_total);
    }

    public function test_count_conflicts_with_changed_stock_and_replays_without_double_adjustment(): void
    {
        $ingredient = $this->ingredient();
        app(StockMovementService::class)->record($ingredient, 'purchase', 2, $this->actor->id);
        $input = $this->payload(['ingredient_id' => $ingredient->id, 'expected_stock' => 2, 'counted_stock' => 1.5, 'reason' => 'Weekly count']);
        $this->postJson('/api/v1/stock/count', $input)->assertOk();
        $this->postJson('/api/v1/stock/count', $input)->assertOk();
        $this->postJson('/api/v1/stock/count', $this->payload(['ingredient_id' => $ingredient->id, 'expected_stock' => 2, 'counted_stock' => 1, 'reason' => 'Stale']))->assertConflict();
        $this->assertEquals(1.5, $ingredient->fresh()->current_stock);
        $this->assertDatabaseCount('stock_movements', 2);
    }

    public function test_transfer_converts_units_and_updates_both_balances_once(): void
    {
        $other = Branch::create(['business_id' => $this->actor->business_id, 'name' => 'Other', 'code' => 'OP-02']);
        $this->actor->branches()->attach($other->id);
        $from = $this->ingredient(); $to = $this->ingredient('Coffee', $other, 'g');
        app(StockMovementService::class)->record($from, 'purchase', 2, $this->actor->id, null, null, 10);
        $input = $this->payload(['source_ingredient_id' => $from->id, 'destination_ingredient_id' => $to->id, 'quantity' => 0.5, 'reason' => 'Delivery']);
        $this->postJson('/api/v1/stock/transfer', $input)->assertOk();
        $this->postJson('/api/v1/stock/transfer', $input)->assertOk();
        $this->assertEquals(1.5, $from->fresh()->current_stock);
        $this->assertEquals(500, $to->fresh()->current_stock);
        $this->assertEquals(0.01, $to->fresh()->average_unit_cost);
    }

    public function test_foreign_branch_and_operator_are_rejected(): void
    {
        $foreign = Branch::create(['business_id' => Business::factory()->create()->id, 'name' => 'Foreign', 'code' => 'OP-X']);
        $this->postJson('/api/v1/shifts', $this->payload(['branch_id' => $foreign->id, 'opening_cash' => 0]))->assertForbidden();
        $this->postJson('/api/v1/shifts', $this->payload(['opening_cash' => 0, 'expected_user_id' => $this->actor->id + 100]))->assertForbidden();
    }

    public function test_cashier_without_refund_permission_cannot_issue_refund(): void
    {
        $order = $this->order(); $this->actor->revokePermissionTo('orders.refund');
        $this->postJson("/api/v1/orders/{$order->id}/refund", $this->payload(['amount' => 10, 'reason' => 'No permission', 'inventory_disposition' => 'consumed']))->assertForbidden();
    }

    public function test_closed_original_shift_rejects_late_payment(): void
    {
        $id = $this->open();
        $this->postJson("/api/v1/shifts/$id/close", $this->payload(['counted_cash' => 20]))->assertOk();
        $this->open();
        $request = \Illuminate\Http\Request::create('/api/v1/orders', 'POST', ['shift_id' => $id]);
        $this->app->instance('request', $request);
        $this->expectException(\Symfony\Component\HttpKernel\Exception\HttpException::class);
        app(\App\Services\ShiftService::class)->paymentShift($this->branch->id, $this->actor->id);
    }

    public function test_variant_recipe_multiplier_snapshots_cost_and_usage(): void
    {
        $ingredient = $this->ingredient();
        app(StockMovementService::class)->record($ingredient, 'purchase', 2, $this->actor->id, null, null, 10);
        $category = Category::create(['business_id' => $this->actor->business_id, 'name' => 'Coffee']);
        $product = Product::create(['business_id' => $this->actor->business_id, 'category_id' => $category->id, 'name' => 'Latte', 'base_price' => 5, 'is_active' => true]);
        $variant = ProductVariant::create(['product_id' => $product->id, 'name' => 'Large', 'price_delta' => 1, 'recipe_multiplier' => 2, 'is_active' => true]);
        RecipeItem::create(['branch_id' => $this->branch->id, 'product_id' => $product->id, 'ingredient_id' => $ingredient->id, 'quantity_used' => 0.1]);
        $order = $this->order();
        $item = OrderItem::create(['order_id' => $order->id, 'product_id' => $product->id, 'product_variant_id' => $variant->id, 'quantity' => 2, 'unit_price' => 6]);
        app(SaleInventoryService::class)->deductForOrder($order, $this->actor->id);
        $this->assertEquals(1.6, $ingredient->fresh()->current_stock);
        $this->assertEquals(4, $item->fresh()->ingredient_cost);
        RecipeItem::query()->update(['quantity_used' => 0.2]);
        $this->assertEquals(4, $item->fresh()->ingredient_cost);
    }
}
