<?php

namespace Tests\Feature;

use App\Models\{Business, Branch, CashierShift, Category, Ingredient, Order, Product, User, Unit};
use App\Services\TenantIntegrity;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\TestCase;

class LaunchBusinessIsolationTest extends TestCase
{
    use RefreshDatabase;

    public function test_foreign_operations_endpoints_deny_admin_and_preserve_records(): void
    {
        $this->seed(RolePermissionSeeder::class);
        $actors = [];
        foreach ([1, 2] as $number) {
            $business = Business::factory()->create();
            $branch = Branch::factory()->create(['business_id' => $business->id]);
            $user = User::factory()->create(['business_id' => $business->id]);
            $user->assignRole('admin');
            $user->branches()->attach($branch->id);
            $actors[] = [$user, $branch];
        }
        [[$a, $branchA], [$b, $branchB]] = $actors;
        $this->actingAs($b);
        $order = Order::create(['uuid' => (string) Str::uuid(), 'branch_id' => $branchB->id, 'user_id' => $b->id,
            'order_type' => 'takeaway', 'status' => 'completed', 'subtotal' => 10, 'total' => 10]);
        $shift = CashierShift::create(['branch_id' => $branchB->id, 'user_id' => $b->id, 'opening_cash' => 20]);
        $unit = Unit::create(['name' => 'kg', 'abbreviation' => 'kg', 'conversion_factor' => 1]);
        $ingredient = Ingredient::create(['branch_id' => $branchB->id, 'unit_id' => $unit->id, 'name' => 'Private beans', 'is_active' => true]);
        $this->actingAs($a);
        foreach (['shifts', 'reports/operations', 'products/availability', 'reports', 'dashboard', 'orders', 'ingredients'] as $endpoint) {
            $this->getJson('/api/v1/'.$endpoint.'?branch_id='.$branchB->id)->assertForbidden();
        }
        $own = ['uuid' => (string) Str::uuid(), 'branch_id' => $branchA->id];
        $this->getJson('/api/v1/orders/'.$order->id.'/financials?branch_id='.$branchA->id)->assertNotFound();
        $this->postJson('/api/v1/orders/'.$order->id.'/refund', $own + ['amount' => 1, 'reason' => 'No', 'inventory_disposition' => 'consumed'])->assertNotFound();
        $this->postJson('/api/v1/shifts/'.$shift->id.'/close', $own + ['counted_cash' => 20])->assertNotFound();
        $this->postJson('/api/v1/stock/count', $own + ['ingredient_id' => $ingredient->id, 'expected_stock' => 0, 'counted_stock' => 1, 'reason' => 'No'])->assertNotFound();
        $this->getJson('/api/v1/ingredients/'.$ingredient->id.'/movements')->assertNotFound();
        $this->assertDatabaseCount('payment_refunds', 0);
        $this->assertDatabaseCount('stock_movements', 0);
        $this->assertDatabaseHas('cashier_shifts', ['id' => $shift->id, 'status' => 'open']);
        $this->assertTrue(app(TenantIntegrity::class)->report()['ready']);
        DB::table('cashier_shifts')->where('id', $shift->id)->update(['user_id' => $a->id]);
        $report = app(TenantIntegrity::class)->report();
        $this->assertFalse($report['ready']);
        $this->assertSame(1, $report['cross_business_links']['cashier_shifts_actor']);
    }
}
