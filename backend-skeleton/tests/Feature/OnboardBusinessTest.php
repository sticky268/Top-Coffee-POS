<?php

namespace Tests\Feature;

use App\Models\{Business, User};
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class OnboardBusinessTest extends TestCase
{
    use RefreshDatabase;

    public function test_onboarding_creates_separate_owners_and_strict_controls_without_shared_data(): void
    {
        $this->seed(RolePermissionSeeder::class);
        foreach (['first', 'second'] as $name) {
            $this->artisan('pos:onboard-business', ['name' => $name, '--owner' => 'Owner', '--email' => $name.'@example.test'])
                ->expectsQuestion('Owner password (at least 12 characters)', 'private-test-password')
                ->expectsQuestion('Confirm owner password', 'private-test-password')
                ->assertSuccessful();
        }
        $this->assertDatabaseCount('businesses', 2);
        $this->assertDatabaseCount('branches', 2);
        $this->assertDatabaseCount('users', 2);
        $this->assertDatabaseCount('products', 0);
        $this->assertDatabaseCount('orders', 0);
        foreach (User::all() as $owner) {
            $this->assertTrue(Hash::check('private-test-password', $owner->password));
            $this->assertTrue($owner->hasRole('admin'));
            $this->assertTrue($owner->business->require_cash_shift);
            $this->assertTrue($owner->business->require_manager_controls);
            $this->assertSame($owner->business_id, $owner->branches()->first()->business_id);
            $this->assertNotNull($owner->business->expires_at);
        }
        $this->assertNotEquals(User::first()->business_id, User::orderByDesc('id')->first()->business_id);
        $this->assertTrue(app(\App\Services\TenantIntegrity::class)->report()['ready']);
    }

    public function test_bad_password_does_not_create_partial_business(): void
    {
        $this->seed(RolePermissionSeeder::class);
        $this->artisan('pos:onboard-business', ['name' => 'No partial writes', '--owner' => 'Owner', '--email' => 'owner@example.test'])
            ->expectsQuestion('Owner password (at least 12 characters)', 'short')
            ->expectsQuestion('Confirm owner password', 'short')->assertFailed();
        $this->assertDatabaseCount('businesses', 0);
        $this->assertDatabaseCount('users', 0);
    }
}
