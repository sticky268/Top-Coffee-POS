<?php

namespace Tests\Unit;

use App\Models\Business;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class BusinessSubscriptionTest extends TestCase
{
    use RefreshDatabase;

    public function test_trial_business_with_no_expiry_is_active(): void
    {
        $business = Business::factory()->create([
            'status' => 'trial',
            'expires_at' => null,
            'is_active' => true,
        ]);

        $this->assertSame('trial', $business->subscriptionStatus());
        $this->assertTrue($business->subscriptionIsActive());
        $this->assertFalse($business->subscriptionIsExpired());
        $this->assertTrue($business->canModifyData());
    }

    public function test_active_business_with_future_expiry_is_active(): void
    {
        $business = Business::factory()->create([
            'status' => 'active',
            'expires_at' => Carbon::now()->addMonth(),
            'is_active' => true,
        ]);

        $this->assertSame('active', $business->subscriptionStatus());
        $this->assertTrue($business->subscriptionIsActive());
        $this->assertFalse($business->subscriptionIsExpired());
        $this->assertTrue($business->canModifyData());
    }

    public function test_expired_business_is_read_only(): void
    {
        $business = Business::factory()->create([
            'status' => 'active',
            'expires_at' => Carbon::now()->subDay(),
            'is_active' => true,
        ]);

        $this->assertSame('expired', $business->subscriptionStatus());
        $this->assertFalse($business->subscriptionIsActive());
        $this->assertTrue($business->subscriptionIsExpired());
        $this->assertFalse($business->canModifyData());
    }

    public function test_suspended_business_is_read_only(): void
    {
        $business = Business::factory()->create([
            'status' => 'suspended',
            'expires_at' => Carbon::now()->addMonth(),
            'is_active' => true,
        ]);

        $this->assertSame('suspended', $business->subscriptionStatus());
        $this->assertFalse($business->subscriptionIsActive());
        $this->assertFalse($business->subscriptionIsExpired());
        $this->assertFalse($business->canModifyData());
    }

    public function test_inactive_business_cannot_modify_data_even_with_active_subscription(): void
    {
        $business = Business::factory()->create([
            'status' => 'active',
            'expires_at' => Carbon::now()->addMonth(),
            'is_active' => false,
        ]);

        $this->assertSame('active', $business->subscriptionStatus());
        $this->assertTrue($business->subscriptionIsActive());
        $this->assertFalse($business->canModifyData());
    }
}