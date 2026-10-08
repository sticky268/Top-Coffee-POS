<?php

namespace Tests\Feature;

use App\Models\Branch;
use App\Models\Business;
use App\Models\LoyaltySetting;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Spatie\Permission\Models\Permission;
use Spatie\Permission\Models\Role;
use Tests\TestCase;

class LoyaltyTest extends TestCase
{
    use RefreshDatabase;

    private Business $business;

    protected function setUp(): void
    {
        parent::setUp();

        $this->business = Business::factory()->create();
    }

    private function createBranch(string $name, string $code): Branch
    {
        return Branch::create([
            'business_id' => $this->business->id,
            'name' => $name,
            'code' => $code,
        ]);
    }
    private function makeLoyaltyUser(Branch $branch): User
    {
        Permission::firstOrCreate([
            'name' => 'loyalty.manage',
            'guard_name' => 'web',
        ]);

        Role::firstOrCreate([
            'name' => 'manager',
            'guard_name' => 'web',
        ]);

        $user = User::factory()->create(['business_id' => $branch->business_id]);
        $user->assignRole('manager');
        $user->givePermissionTo('loyalty.manage');
        $user->branches()->attach($branch->id, ['is_primary' => true]);

        return $user;
    }

    public function test_get_settings_returns_default_branch_settings(): void
    {
        $branch = $this->createBranch('Riverside', 'PP-01');

        $user = $this->makeLoyaltyUser($branch);

        $response = $this->actingAs($user)
            ->getJson('/api/v1/loyalty/settings');

        $response
            ->assertStatus(200)
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.branch_id', $branch->id)
            ->assertJsonPath('data.is_enabled', false)
            ->assertJsonPath('data.points_per_currency_unit', '1.0000')
            ->assertJsonPath('data.points_per_reward_currency_unit', '100.0000')
            ->assertJsonPath('data.minimum_redeem_points', 100)
            ->assertJsonPath('data.redemption_enabled', true)
            ->assertJsonPath('data.expiration_months', null);

        $this->assertDatabaseHas('loyalty_settings', [
            'branch_id' => $branch->id,
            'is_enabled' => false,
            'minimum_redeem_points' => 100,
            'redemption_enabled' => true,
        ]);
    }

    public function test_update_settings_saves_loyalty_rules(): void
    {
        $branch = $this->createBranch('Riverside', 'PP-01');

        $user = $this->makeLoyaltyUser($branch);

        $response = $this->actingAs($user)
            ->patchJson(
                '/api/v1/loyalty/settings',
                [
                    'is_enabled' => true,
                    'points_per_currency_unit' => 2.5,
                    'points_per_reward_currency_unit' => 50,
                    'minimum_redeem_points' => 200,
                    'redemption_enabled' => false,
                    'expiration_months' => 12,
                ],
            );

        $response
            ->assertStatus(200)
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.branch_id', $branch->id)
            ->assertJsonPath('data.is_enabled', true)
            ->assertJsonPath('data.points_per_currency_unit', '2.5000')
            ->assertJsonPath('data.points_per_reward_currency_unit', '50.0000')
            ->assertJsonPath('data.minimum_redeem_points', 200)
            ->assertJsonPath('data.redemption_enabled', false)
            ->assertJsonPath('data.expiration_months', 12);

        $this->assertDatabaseHas('loyalty_settings', [
            'branch_id' => $branch->id,
            'is_enabled' => true,
            'points_per_currency_unit' => 2.5,
            'points_per_reward_currency_unit' => 50,
            'minimum_redeem_points' => 200,
            'redemption_enabled' => false,
            'expiration_months' => 12,
        ]);
    }


    public function test_update_settings_rejects_invalid_values(): void
    {
        $branch = $this->createBranch('Riverside', 'PP-01');

        $user = $this->makeLoyaltyUser($branch);

        $response = $this->actingAs($user)
            ->patchJson(
                '/api/v1/loyalty/settings',
                [
                    'points_per_currency_unit' => -1,
                    'expiration_months' => 121,
                ],
            );

        $response
            ->assertStatus(422)
            ->assertJsonPath('success', false)
            ->assertJsonPath('message', 'Validation failed');

        $this->assertDatabaseCount('loyalty_settings', 0);
    }

}
