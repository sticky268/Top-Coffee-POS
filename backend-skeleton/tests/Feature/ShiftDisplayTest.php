<?php

namespace Tests\Feature;

use App\Models\{Branch, Business, CashierShift, User};
use Illuminate\Foundation\Testing\RefreshDatabase;
use Spatie\Permission\Models\Permission;
use Tests\TestCase;

class ShiftDisplayTest extends TestCase
{
    use RefreshDatabase;

    public function test_shift_list_includes_names_only_for_shifts_the_actor_can_view(): void
    {
        $business = Business::factory()->create();
        $branch = Branch::create(['business_id' => $business->id, 'name' => 'Cafe', 'code' => 'SD-01']);
        $otherBranch = Branch::create(['business_id' => $business->id, 'name' => 'Other', 'code' => 'SD-02']);
        $actor = User::factory()->create(['business_id' => $business->id, 'name' => 'Sophea']);
        $colleague = User::factory()->create(['business_id' => $business->id, 'name' => 'Dara']);
        $actor->branches()->attach($branch->id);
        foreach (['orders.create', 'reports.view'] as $name) {
            Permission::firstOrCreate(['name' => $name, 'guard_name' => 'web']);
        }
        $actor->givePermissionTo('orders.create');
        $own = CashierShift::create(['branch_id' => $branch->id, 'user_id' => $actor->id, 'opening_cash' => 10]);
        $team = CashierShift::create(['branch_id' => $branch->id, 'user_id' => $colleague->id, 'opening_cash' => 20]);
        CashierShift::create(['branch_id' => $otherBranch->id, 'user_id' => $colleague->id, 'opening_cash' => 30]);
        $this->actingAs($actor);

        $this->getJson('/api/v1/shifts?branch_id='.$branch->id)
            ->assertOk()->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.id', $own->id)
            ->assertJsonPath('data.0.cashier_name', 'Sophea')
            ->assertJsonMissingPath('data.0.cashier')
            ->assertJsonMissingPath('data.0.email');

        $actor->givePermissionTo('reports.view');
        $response = $this->getJson('/api/v1/shifts?branch_id='.$branch->id)
            ->assertOk()->assertJsonCount(2, 'data');
        $rows = collect($response->json('data'))->keyBy('id');
        $this->assertSame('Sophea', $rows[$own->id]['cashier_name']);
        $this->assertSame('Dara', $rows[$team->id]['cashier_name']);
        $this->getJson('/api/v1/shifts?branch_id='.$otherBranch->id)->assertForbidden();
    }

    public function test_shift_names_are_eager_loaded_without_serializing_user_records(): void
    {
        $business = Business::factory()->create();
        $branch = Branch::create(['business_id' => $business->id, 'name' => 'Cafe', 'code' => 'SD-03']);
        $actor = User::factory()->create(['business_id' => $business->id]);
        $actor->branches()->attach($branch->id);
        Permission::firstOrCreate(['name' => 'reports.view', 'guard_name' => 'web']);
        $actor->givePermissionTo('reports.view');
        foreach (['Cashier A', 'Cashier B'] as $name) {
            $cashier = User::factory()->create(['business_id' => $business->id, 'name' => $name]);
            CashierShift::create(['branch_id' => $branch->id, 'user_id' => $cashier->id, 'opening_cash' => 0]);
        }
        $this->actingAs($actor);

        $queries = [];
        \Illuminate\Support\Facades\DB::listen(function ($query) use (&$queries) {
            if (str_contains(strtolower($query->sql), 'from "users"') ||
                str_contains(strtolower($query->sql), 'from `users`')) {
                $queries[] = $query->sql;
            }
        });
        $this->getJson('/api/v1/shifts?branch_id='.$branch->id)
            ->assertOk()->assertJsonCount(2, 'data')
            ->assertJsonMissingPath('data.0.cashier')
            ->assertJsonMissingPath('data.1.cashier');
        $this->assertCount(1, $queries);
    }
}
