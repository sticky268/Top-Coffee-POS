<?php

namespace Tests\Feature;

use App\Models\Branch;
use App\Models\Business;
use App\Models\RestaurantTable;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Spatie\Permission\Models\Permission;
use Tests\TestCase;

class TableBranchIsolationTest extends TestCase
{
    use RefreshDatabase;

    private function setupUser(): array
    {
        Permission::firstOrCreate(['name' => 'tables.manage', 'guard_name' => 'web']);

        $business = Business::factory()->create();
        $branchA = Branch::create([
            'business_id' => $business->id,
            'name' => 'Branch A',
            'code' => 'TBA',
        ]);
        $branchB = Branch::create([
            'business_id' => $business->id,
            'name' => 'Branch B',
            'code' => 'TBB',
        ]);

        $user = User::factory()->create(['business_id' => $business->id]);
        $user->givePermissionTo('tables.manage');
        $user->branches()->attach($branchA->id, ['is_primary' => true]);
        $user->branches()->attach($branchB->id, ['is_primary' => false]);

        return [$user, $branchA, $branchB];
    }

    public function test_table_list_is_scoped_to_explicit_selected_branch(): void
    {
        [$user, $branchA, $branchB] = $this->setupUser();

        RestaurantTable::create([
            'branch_id' => $branchA->id,
            'name' => 'A1',
            'capacity' => 4,
            'status' => 'available',
            'is_active' => true,
        ]);
        $tableB = RestaurantTable::create([
            'branch_id' => $branchB->id,
            'name' => 'B1',
            'capacity' => 4,
            'status' => 'available',
            'is_active' => true,
        ]);

        $response = $this->actingAs($user)
            ->getJson("/api/v1/tables?branch_id={$branchB->id}")
            ->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.id', $tableB->id)
            ->assertJsonPath('data.0.branch_id', $branchB->id);

        $this->assertSame('B1', $response->json('data.0.name'));
    }

    public function test_user_cannot_request_tables_from_unassigned_branch(): void
    {
        [$user, $branchA] = $this->setupUser();
        $otherBusiness = Business::factory()->create();
        $foreign = Branch::create([
            'business_id' => $otherBusiness->id,
            'name' => 'Foreign',
            'code' => 'TBF',
        ]);

        $this->actingAs($user)
            ->getJson("/api/v1/tables?branch_id={$foreign->id}")
            ->assertForbidden();

        $this->actingAs($user)
            ->getJson("/api/v1/tables?branch_id={$branchA->id}")
            ->assertOk();
    }

    public function test_table_mutation_cannot_target_table_from_different_selected_branch(): void
    {
        [$user, $branchA, $branchB] = $this->setupUser();
        $tableB = RestaurantTable::create([
            'branch_id' => $branchB->id,
            'name' => 'B1',
            'capacity' => 4,
            'status' => 'available',
            'is_active' => true,
        ]);

        $this->actingAs($user)
            ->patchJson("/api/v1/tables/{$tableB->id}", [
                'branch_id' => $branchA->id,
                'name' => 'Changed',
            ])
            ->assertNotFound();

        $this->assertSame('B1', $tableB->fresh()->name);
    }
}
