<?php

namespace Tests\Feature;

use App\Models\Branch;
use App\Models\Business;
use App\Models\Plan;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Spatie\Permission\Models\Permission;
use Spatie\Permission\Models\Role;
use Tests\TestCase;

class BranchTest extends TestCase
{
    use RefreshDatabase;

    private Business $business;

    protected function setUp(): void
    {
        parent::setUp();

        $plans = [
            [
                'name' => '1 Branch',
                'slug' => '1-branch',
                'branch_limit' => 1,
            ],
            [
                'name' => '2 Branches',
                'slug' => '2-branches',
                'branch_limit' => 2,
            ],
            [
                'name' => '3 Branches',
                'slug' => '3-branches',
                'branch_limit' => 3,
            ],
            [
                'name' => '4 Branches',
                'slug' => '4-branches',
                'branch_limit' => 4,
            ],
            [
                'name' => '5 Branches',
                'slug' => '5-branches',
                'branch_limit' => 5,
            ],
            [
                'name' => '10 Branches',
                'slug' => '10-branches',
                'branch_limit' => 10,
            ],
        ];

        foreach ($plans as $plan) {
            Plan::create(array_merge($plan, [
                'price' => 0,
                'billing_interval' => 'monthly',
                'is_active' => true,
            ]));
        }

        $this->business = Business::factory()->create([
            'plan_id' => Plan::where('slug', '1-branch')->firstOrFail()->id,
        ]);
    }

    private function setupPermissions(): void
    {
        foreach (['branches.manage'] as $permission) {
            Permission::firstOrCreate([
                'name' => $permission,
                'guard_name' => 'web',
            ]);
        }

        foreach (['admin', 'manager', 'cashier'] as $role) {
            Role::firstOrCreate([
                'name' => $role,
                'guard_name' => 'web',
            ]);
        }
    }

    private function makeUser(bool $canManageBranches = true): User
    {
        $this->setupPermissions();

        $role = Role::where('name', 'admin')->firstOrFail();

        $role->syncPermissions(
            $canManageBranches ? ['branches.manage'] : []
        );

        $user = User::factory()->create([
            'business_id' => $this->business->id,
            'is_active' => true,
        ]);

        $user->assignRole($role);

        return $user;
    }

    public function test_unauthenticated_request_is_rejected(): void
    {
        $this->getJson('/api/v1/branches')
            ->assertStatus(401);
    }

    public function test_user_without_branches_manage_permission_is_rejected(): void
    {
        $user = $this->makeUser(false);

        $this->actingAs($user)
            ->getJson('/api/v1/branches')
            ->assertStatus(403)
            ->assertJsonPath('success', false);
    }

    public function test_authorized_user_can_list_branches(): void
    {
        $user = $this->makeUser();

        Branch::create([
            'business_id' => $this->business->id,
            'name' => 'Riverside',
            'code' => 'PP-01',
        ]);

        Branch::create([
            'business_id' => $this->business->id,
            'name' => 'BKK1',
            'code' => 'PP-02',
        ]);

        $response = $this->actingAs($user)
            ->getJson('/api/v1/branches');

        $response
            ->assertStatus(200)
            ->assertJsonPath('success', true)
            ->assertJsonCount(2, 'data')
            ->assertJsonPath('meta.total', 2);
    }

    public function test_admin_can_only_list_branches_from_own_business(): void
    {
        $user = $this->makeUser();

        Branch::create([
            'business_id' => $this->business->id,
            'name' => 'Business A Branch',
            'code' => 'A-01',
        ]);

        $businessB = Business::factory()->create();

        Branch::create([
            'business_id' => $businessB->id,
            'name' => 'Business B Branch',
            'code' => 'B-01',
        ]);

        $response = $this->actingAs($user)
            ->getJson('/api/v1/branches');

        $response
            ->assertStatus(200)
            ->assertJsonPath('success', true)
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.name', 'Business A Branch')
            ->assertJsonMissing([
                'name' => 'Business B Branch',
            ]);
    }
    public function test_branch_list_supports_search_and_active_filter(): void
    {
        $user = $this->makeUser();

        Branch::create([
            'business_id' => $this->business->id,
            'name' => 'Riverside',
            'code' => 'PP-01',
            'is_active' => true,
        ]);

        Branch::create([
            'business_id' => $this->business->id,
            'name' => 'BKK1',
            'code' => 'PP-02',
            'is_active' => false,
        ]);

        $searchResponse = $this->actingAs($user)
            ->getJson('/api/v1/branches?search=Riverside');

        $searchResponse
            ->assertStatus(200)
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.code', 'PP-01');

        $activeResponse = $this->actingAs($user)
            ->getJson('/api/v1/branches?is_active=1');

        $activeResponse
            ->assertStatus(200)
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.code', 'PP-01');
    }

    public function test_admin_cannot_access_branch_from_another_business(): void
    {
        $user = $this->makeUser();

        $businessB = Business::factory()->create();

        $branchB = Branch::create([
            'business_id' => $businessB->id,
            'name' => 'Business B Branch',
            'code' => 'B-02',
        ]);

        $this->actingAs($user)
            ->getJson("/api/v1/branches/{$branchB->id}")
            ->assertStatus(403)
            ->assertJsonPath('success', false);

        $this->actingAs($user)
            ->patchJson("/api/v1/branches/{$branchB->id}", [
                'name' => 'Changed By Business A',
            ])
            ->assertStatus(403)
            ->assertJsonPath('success', false);

        $this->actingAs($user)
            ->deleteJson("/api/v1/branches/{$branchB->id}")
            ->assertStatus(403)
            ->assertJsonPath('success', false);

        $this->assertDatabaseHas('branches', [
            'id' => $branchB->id,
            'business_id' => $businessB->id,
            'name' => 'Business B Branch',
            'deleted_at' => null,
        ]);
    }
    public function test_branch_creation_is_blocked_when_plan_limit_is_reached(): void
    {
        $user = $this->makeUser();

        Branch::create([
            'business_id' => $this->business->id,
            'name' => 'Existing Branch',
            'code' => 'PP-01',
            'timezone' => 'Asia/Phnom_Penh',
        ]);

        $response = $this->actingAs($user)
            ->postJson('/api/v1/branches', [
                'name' => 'Second Branch',
                'code' => 'PP-02',
                'timezone' => 'Asia/Phnom_Penh',
            ]);

        $response
            ->assertStatus(403)
            ->assertJsonPath('success', false)
            ->assertJsonPath('code', 'BRANCH_LIMIT_REACHED')
            ->assertJsonPath('branch_limit', 1)
            ->assertJsonPath('branch_count', 1);
    }

    public function test_branch_creation_is_blocked_when_business_has_no_plan(): void
    {
        $user = $this->makeUser();

        $this->business->update([
            'plan_id' => null,
        ]);

        $response = $this->actingAs($user)
            ->postJson('/api/v1/branches', [
                'name' => 'New Branch',
                'code' => 'PP-99',
                'timezone' => 'Asia/Phnom_Penh',
            ]);

        $response
            ->assertStatus(403)
            ->assertJsonPath('success', false)
            ->assertJsonPath('code', 'PLAN_REQUIRED');
    }

    public function test_two_branch_plan_allows_two_branches_but_blocks_third(): void
    {
        $user = $this->makeUser();

        $plan = Plan::where('slug', '2-branches')->firstOrFail();

        $this->business->update([
            'plan_id' => $plan->id,
        ]);

        $this->actingAs($user)
            ->postJson('/api/v1/branches', [
                'name' => 'Branch One',
                'code' => 'PP-01',
                'timezone' => 'Asia/Phnom_Penh',
            ])
            ->assertStatus(201);

        $this->actingAs($user)
            ->postJson('/api/v1/branches', [
                'name' => 'Branch Two',
                'code' => 'PP-02',
                'timezone' => 'Asia/Phnom_Penh',
            ])
            ->assertStatus(201);

        $response = $this->actingAs($user)
            ->postJson('/api/v1/branches', [
                'name' => 'Branch Three',
                'code' => 'PP-03',
                'timezone' => 'Asia/Phnom_Penh',
            ]);

        $response
            ->assertStatus(403)
            ->assertJsonPath('code', 'BRANCH_LIMIT_REACHED')
            ->assertJsonPath('branch_limit', 2)
            ->assertJsonPath('branch_count', 2);
    }

    public function test_ten_branch_plan_allows_ten_branches(): void
    {
        $user = $this->makeUser();

        $plan = Plan::where('slug', '10-branches')->firstOrFail();

        $this->business->update([
            'plan_id' => $plan->id,
        ]);

        for ($i = 1; $i <= 10; $i++) {
            $this->actingAs($user)
                ->postJson('/api/v1/branches', [
                    'name' => "Branch {$i}",
                    'code' => sprintf('PP-%02d', $i),
                    'timezone' => 'Asia/Phnom_Penh',
                ])
                ->assertStatus(201);
        }

        $this->assertDatabaseCount('branches', 10);

        $this->actingAs($user)
            ->postJson('/api/v1/branches', [
                'name' => 'Branch 11',
                'code' => 'PP-11',
                'timezone' => 'Asia/Phnom_Penh',
            ])
            ->assertStatus(403)
            ->assertJsonPath('code', 'BRANCH_LIMIT_REACHED')
            ->assertJsonPath('branch_limit', 10)
            ->assertJsonPath('branch_count', 10);
    }
    public function test_authorized_user_can_create_branch(): void
    {
        $user = $this->makeUser();

        $response = $this->actingAs($user)
            ->postJson('/api/v1/branches', [
                'name' => 'Riverside',
                'code' => 'PP-01',
                'address' => 'Phnom Penh',
                'phone' => '012345678',
                'timezone' => 'Asia/Phnom_Penh',
                'is_active' => true,
            ]);

        $response
            ->assertStatus(201)
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.name', 'Riverside')
            ->assertJsonPath('data.code', 'PP-01')
            ->assertJsonPath('data.is_active', true)
            ->assertJsonPath('data.users_count', 0);

        $this->assertDatabaseHas('branches', [
            'name' => 'Riverside',
            'code' => 'PP-01',
        ]);
    }

    public function test_created_branch_always_uses_authenticated_business(): void
    {
        $user = $this->makeUser();

        $businessB = Business::factory()->create();

        $response = $this->actingAs($user)
            ->postJson('/api/v1/branches', [
                'name' => 'Business A New Branch',
                'code' => 'A-03',
                'timezone' => 'Asia/Phnom_Penh',
                'business_id' => $businessB->id,
            ]);

        $response
            ->assertStatus(201)
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.name', 'Business A New Branch');

        $this->assertDatabaseHas('branches', [
            'name' => 'Business A New Branch',
            'code' => 'A-03',
            'business_id' => $this->business->id,
        ]);

        $this->assertDatabaseMissing('branches', [
            'name' => 'Business A New Branch',
            'code' => 'A-03',
            'business_id' => $businessB->id,
        ]);
    }
    public function test_duplicate_branch_code_is_rejected(): void
    {
        $user = $this->makeUser();

        Branch::create([
            'business_id' => $this->business->id,
            'name' => 'Riverside',
            'code' => 'PP-01',
        ]);

        $this->actingAs($user)
            ->postJson('/api/v1/branches', [
                'name' => 'Another Branch',
                'code' => 'PP-01',
                'timezone' => 'Asia/Phnom_Penh',
            ])
            ->assertStatus(422)
            ->assertJsonPath('success', false);
    }

    public function test_authorized_user_can_show_branch(): void
    {
        $user = $this->makeUser();

        $branch = Branch::create([
            'business_id' => $this->business->id,
            'name' => 'Riverside',
            'code' => 'PP-01',
        ]);

        $this->actingAs($user)
            ->getJson("/api/v1/branches/{$branch->id}")
            ->assertStatus(200)
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.id', $branch->id)
            ->assertJsonPath('data.name', 'Riverside')
            ->assertJsonPath('data.users_count', 0);
    }

    public function test_authorized_user_can_update_branch(): void
    {
        $user = $this->makeUser();

        $branch = Branch::create([
            'business_id' => $this->business->id,
            'name' => 'Riverside',
            'code' => 'PP-01',
        ]);

        $this->actingAs($user)
            ->patchJson("/api/v1/branches/{$branch->id}", [
                'name' => 'Riverside Updated',
                'phone' => '099999999',
                'is_active' => false,
            ])
            ->assertStatus(200)
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.name', 'Riverside Updated')
            ->assertJsonPath('data.phone', '099999999')
            ->assertJsonPath('data.is_active', false);

        $this->assertDatabaseHas('branches', [
            'id' => $branch->id,
            'name' => 'Riverside Updated',
            'phone' => '099999999',
            'is_active' => false,
        ]);
    }

    public function test_authorized_user_can_delete_branch_without_users(): void
    {
        $user = $this->makeUser();

        $branch = Branch::create([
            'business_id' => $this->business->id,
            'name' => 'Riverside',
            'code' => 'PP-01',
        ]);

        $this->actingAs($user)
            ->deleteJson("/api/v1/branches/{$branch->id}")
            ->assertStatus(200)
            ->assertJsonPath('success', true);

        $this->assertSoftDeleted('branches', [
            'id' => $branch->id,
        ]);
    }

    public function test_three_four_and_five_branch_plans_enforce_their_limits(): void
    {
        foreach ([3, 4, 5] as $limit) {
            $plan = Plan::where('branch_limit', $limit)->firstOrFail();

            $business = Business::factory()->create([
                'plan_id' => $plan->id,
            ]);

            $user = User::factory()->create([
                'business_id' => $business->id,
                'is_active' => true,
            ]);

            $this->setupPermissions();

            $role = Role::where('name', 'admin')->firstOrFail();
            $role->syncPermissions(['branches.manage']);
            $user->assignRole($role);

            for ($i = 1; $i <= $limit; $i++) {
                $this->actingAs($user)
                    ->postJson('/api/v1/branches', [
                        'name' => "Branch {$limit}-{$i}",
                        'code' => sprintf('P%d-%02d', $limit, $i),
                        'timezone' => 'Asia/Phnom_Penh',
                    ])
                    ->assertStatus(201);
            }

            $response = $this->actingAs($user)
                ->postJson('/api/v1/branches', [
                    'name' => "Branch {$limit}-" . ($limit + 1),
                    'code' => sprintf('P%d-%02d', $limit, $limit + 1),
                    'timezone' => 'Asia/Phnom_Penh',
                ]);

            $response
                ->assertStatus(403)
                ->assertJsonPath('code', 'BRANCH_LIMIT_REACHED')
                ->assertJsonPath('branch_limit', $limit)
                ->assertJsonPath('branch_count', $limit);
        }
    }
    public function test_branch_with_assigned_users_cannot_be_deleted(): void
    {
        $user = $this->makeUser();

        $branch = Branch::create([
            'business_id' => $this->business->id,
            'name' => 'Riverside',
            'code' => 'PP-01',
        ]);

        $staff = User::factory()->create([
            'business_id' => $this->business->id,
            'is_active' => true,
        ]);

        $branch->users()->attach($staff->id, [
            'is_primary' => true,
        ]);

        $this->actingAs($user)
            ->deleteJson("/api/v1/branches/{$branch->id}")
            ->assertStatus(422)
            ->assertJsonPath('success', false);

        $this->assertDatabaseHas('branches', [
            'id' => $branch->id,
            'deleted_at' => null,
        ]);
    }
}