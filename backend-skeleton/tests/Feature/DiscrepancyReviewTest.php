<?php
namespace Tests\Feature;

use App\Models\{Branch, Business, CashierShift, User};
use Illuminate\Foundation\Testing\RefreshDatabase;
use Spatie\Permission\Models\Permission;
use Tests\TestCase;

class DiscrepancyReviewTest extends TestCase
{
    use RefreshDatabase;

    public function test_branch_scoped_cash_variances_link_to_source_shifts(): void
    {
        $business = Business::factory()->create();
        $branch = Branch::factory()->create(['business_id' => $business->id, 'timezone' => 'UTC']);
        $other = Branch::factory()->create(['business_id' => $business->id]);
        $actor = User::factory()->create(['business_id' => $business->id]);
        $actor->branches()->attach($branch->id);
        foreach (['orders.view', 'reports.view'] as $name) {
            Permission::firstOrCreate(['name' => $name, 'guard_name' => 'web']);
            $actor->givePermissionTo($name);
        }
        $shift = CashierShift::create([
            'branch_id' => $branch->id, 'user_id' => $actor->id,
            'status' => 'closed', 'opening_cash' => 10,
            'expected_cash' => 10, 'counted_cash' => 8,
            'difference' => -2, 'closed_at' => now(),
        ]);
        CashierShift::create([
            'branch_id' => $other->id, 'user_id' => $actor->id,
            'status' => 'closed', 'opening_cash' => 10,
            'difference' => 7, 'closed_at' => now(),
        ]);
        $this->actingAs($actor)->getJson("/api/v1/dashboard?branch_id={$branch->id}")
            ->assertOk()
            ->assertJsonPath('data.stats.cash_discrepancy_count', 1)
            ->assertJsonPath('data.stats.cash_discrepancy_shift_id', $shift->id);
        $day = now()->utc()->format('Y-m-d');
        $this->getJson("/api/v1/reports/operations?branch_id={$branch->id}&date_from={$day}&date_to={$day}")
            ->assertOk()
            ->assertJsonPath('data.cash_difference_shift_count', 1)
            ->assertJsonPath('data.cash_difference_shifts.0.id', $shift->id);
        $this->getJson("/api/v1/shifts?branch_id={$branch->id}&shift_id={$shift->id}")
            ->assertOk()->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.id', $shift->id);
        $this->getJson("/api/v1/shifts?branch_id={$other->id}&shift_id={$shift->id}")
            ->assertForbidden();
        $actor->revokePermissionTo('reports.view');
        $this->getJson("/api/v1/dashboard?branch_id={$branch->id}")
            ->assertOk()->assertJsonPath('data.stats.cash_discrepancy_count', 0);
    }

    public function test_cash_refund_links_point_to_the_orders_deducted_from_this_shift(): void
    {
        $business = Business::factory()->create();
        $branch = Branch::factory()->create(['business_id' => $business->id]);
        $actor = User::factory()->create(['business_id' => $business->id]);
        $actor->branches()->attach($branch->id);
        Permission::firstOrCreate(['name' => 'orders.create', 'guard_name' => 'web']);
        $actor->givePermissionTo('orders.create');
        $shift = CashierShift::create([
            'branch_id' => $branch->id, 'user_id' => $actor->id,
            'status' => 'closed', 'opening_cash' => 10,
        ]);
        $order = \App\Models\Order::create([
            'uuid' => (string) \Illuminate\Support\Str::uuid(),
            'branch_id' => $branch->id, 'user_id' => $actor->id,
            'order_type' => 'takeaway', 'status' => 'completed',
            'subtotal' => 10, 'total' => 10,
        ]);
        $payment = \App\Models\Payment::create([
            'order_id' => $order->id, 'method' => 'cash', 'amount' => 10,
            'status' => 'partially_refunded', 'processed_by' => $actor->id,
            'shift_id' => $shift->id,
        ]);
        \App\Models\PaymentRefund::create([
            'payment_id' => $payment->id, 'amount' => 2,
            'reason' => 'Returned item', 'processed_by' => $actor->id,
            'shift_id' => $shift->id, 'inventory_disposition' => 'consumed',
        ]);
        $this->actingAs($actor)->getJson("/api/v1/shifts?branch_id={$branch->id}&shift_id={$shift->id}")
            ->assertOk()
            ->assertJsonPath('data.0.cash_refunds', 2)
            ->assertJsonCount(1, 'data.0.cash_refund_orders')
            ->assertJsonPath('data.0.cash_refund_orders.0.order_id', $order->id)
            ->assertJsonPath('data.0.cash_refund_orders.0.reason', 'Returned item');
    }

    public function test_stock_count_variances_link_to_exact_ledger_rows_without_mutation(): void
    {
        $business = Business::factory()->create();
        $branch = Branch::factory()->create(['business_id' => $business->id, 'timezone' => 'UTC']);
        $other = Branch::factory()->create(['business_id' => $business->id]);
        $actor = User::factory()->create(['business_id' => $business->id]);
        $actor->branches()->attach($branch->id);
        foreach (['inventory.adjust', 'inventory.view', 'reports.view'] as $name) {
            Permission::firstOrCreate(['name' => $name, 'guard_name' => 'web']);
            $actor->givePermissionTo($name);
        }
        $unit = \App\Models\Unit::create([
            'name' => 'Gram', 'abbreviation' => 'g', 'conversion_factor' => 1,
        ]);
        $ingredient = \App\Models\Ingredient::create([
            'branch_id' => $branch->id, 'unit_id' => $unit->id,
            'name' => 'Milk', 'reorder_threshold' => 1, 'is_active' => true,
        ]);
        $otherIngredient = \App\Models\Ingredient::create([
            'branch_id' => $other->id, 'unit_id' => $unit->id,
            'name' => 'Other milk', 'is_active' => true,
        ]);
        $stock = app(\App\Services\StockMovementService::class);
        $stock->record($ingredient, 'purchase', 5, $actor->id);
        $stock->record($otherIngredient, 'adjustment', 4, $actor->id, 'Stock count: different branch');
        $this->actingAs($actor)->postJson('/api/v1/stock/count', [
            'uuid' => (string) \Illuminate\Support\Str::uuid(),
            'branch_id' => $branch->id,
            'ingredient_id' => $ingredient->id,
            'expected_stock' => 5,
            'counted_stock' => 3,
            'reason' => 'Counted again',
        ])->assertOk();
        $movement = \App\Models\StockMovement::where('ingredient_id', $ingredient->id)
            ->where('type', 'adjustment')->firstOrFail();
        $day = now()->utc()->format('Y-m-d');
        $report = $this->getJson("/api/v1/reports/operations?branch_id={$branch->id}&date_from={$day}&date_to={$day}")
            ->assertOk()
            ->assertJsonPath('data.stock_count_discrepancy_count', 1)
            ->assertJsonPath('data.stock_count_discrepancies.0.id', $movement->id)
            ->assertJsonPath('data.stock_count_discrepancies.0.unit_abbreviation', 'g');
        $this->assertEqualsWithDelta(3, (float) $report->json('data.stock_count_discrepancies.0.balance_after'), 0.001);
        $this->getJson("/api/v1/ingredients/{$ingredient->id}/movements?movement_id={$movement->id}")
            ->assertOk()->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.id', $movement->id);
        $this->getJson("/api/v1/ingredients/{$ingredient->id}/movements?movement_id=999999")
            ->assertOk()->assertJsonCount(0, 'data');
        $this->getJson("/api/v1/ingredients/{$otherIngredient->id}/movements")
            ->assertNotFound();
        $this->assertEquals(3, $ingredient->fresh()->current_stock);
        $this->assertDatabaseCount('stock_movements', 3);
    }
}
