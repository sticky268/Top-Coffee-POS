<?php

namespace Tests\Feature;

use App\Models\Branch;
use App\Models\Business;
use App\Models\Plan;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class SubscriptionTest extends TestCase
{
    use RefreshDatabase;

    private function createPlan(int $branchLimit = 1): Plan
    {
        return Plan::factory()->create([
            'name' => "{$branchLimit} Branch Plan",
            'slug' => "test-{$branchLimit}-branch-plan-" . uniqid(),
            'branch_limit' => $branchLimit,
            'price' => 10,
            'billing_interval' => 'monthly',
            'is_active' => true,
        ]);
    }

    private function createBusiness(array $attributes = [], int $branchLimit = 1): Business
    {
        $plan = $this->createPlan($branchLimit);

        return Business::factory()->create(array_merge([
            'plan_id' => $plan->id,
            'status' => 'trial',
            'started_at' => Carbon::now()->subDays(5),
            'expires_at' => null,
            'is_active' => true,
        ], $attributes));
    }

    private function createUserForBusiness(Business $business): User
    {
        return User::factory()->create([
            'business_id' => $business->id,
        ]);
    }

    public function test_active_business_returns_subscription_details(): void
    {
        $business = $this->createBusiness([
            'status' => 'active',
            'started_at' => Carbon::now()->subDays(10),
            'expires_at' => Carbon::now()->addDays(20),
        ], 3);

        $user = $this->createUserForBusiness($business);

        $response = $this->actingAs($user)
            ->getJson('/api/v1/subscription');

        $response
            ->assertOk()
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.plan.id', $business->plan_id)
            ->assertJsonPath('data.plan.branch_limit', 3)
            ->assertJsonPath('data.plan.billing_interval', 'monthly')
            ->assertJsonPath('data.branch_usage.current', 0)
            ->assertJsonPath('data.branch_usage.limit', 3)
            ->assertJsonPath('data.branch_usage.remaining', 3)
            ->assertJsonPath('data.subscription.status', 'active')
            ->assertJsonPath('data.subscription.is_active', true)
            ->assertJsonPath('data.subscription.is_expired', false)
            ->assertJsonPath('data.subscription.can_modify', true);
    }

    public function test_subscription_returns_current_branch_usage(): void
    {
        $business = $this->createBusiness([], 3);

        Branch::create([
            'business_id' => $business->id,
            'name' => 'Branch One',
            'code' => 'SUB-01',
        ]);

        Branch::create([
            'business_id' => $business->id,
            'name' => 'Branch Two',
            'code' => 'SUB-02',
        ]);

        $user = $this->createUserForBusiness($business);

        $response = $this->actingAs($user)
            ->getJson('/api/v1/subscription');

        $response
            ->assertOk()
            ->assertJsonPath('data.branch_usage.current', 2)
            ->assertJsonPath('data.branch_usage.limit', 3)
            ->assertJsonPath('data.branch_usage.remaining', 1);
    }

    public function test_expired_business_can_read_subscription_details(): void
    {
        $business = $this->createBusiness([
            'status' => 'active',
            'expires_at' => Carbon::now()->subDay(),
        ], 1);

        $user = $this->createUserForBusiness($business);

        $response = $this->actingAs($user)
            ->getJson('/api/v1/subscription');

        $response
            ->assertOk()
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.subscription.status', 'expired')
            ->assertJsonPath('data.subscription.is_active', false)
            ->assertJsonPath('data.subscription.is_expired', true)
            ->assertJsonPath('data.subscription.can_modify', false);
    }

    public function test_suspended_business_can_read_subscription_details(): void
    {
        $business = $this->createBusiness([
            'status' => 'suspended',
            'expires_at' => Carbon::now()->addMonth(),
        ], 2);

        $user = $this->createUserForBusiness($business);

        $response = $this->actingAs($user)
            ->getJson('/api/v1/subscription');

        $response
            ->assertOk()
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.subscription.status', 'suspended')
            ->assertJsonPath('data.subscription.is_active', false)
            ->assertJsonPath('data.subscription.is_expired', false)
            ->assertJsonPath('data.subscription.can_modify', false);
    }

    public function test_unauthenticated_user_cannot_read_subscription(): void
    {
        $response = $this->getJson('/api/v1/subscription');

        $response->assertUnauthorized();
    }

    public function test_subscription_includes_plan_pricing_information(): void
    {
        $business = $this->createBusiness([], 5);

        $business->plan->update([
            'price' => 29.99,
            'billing_interval' => 'monthly',
        ]);

        $user = $this->createUserForBusiness($business);

        $response = $this->actingAs($user)
            ->getJson('/api/v1/subscription');

        $response
            ->assertOk()
            ->assertJsonPath('data.plan.price', '29.99')
            ->assertJsonPath('data.plan.billing_interval', 'monthly')
            ->assertJsonPath('data.plan.is_active', true);
    }
}