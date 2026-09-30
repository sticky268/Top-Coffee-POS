<?php

namespace Tests\Unit;

use App\Http\Middleware\EnsureBusinessSubscriptionActive;
use App\Models\Business;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Http\Request;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Symfony\Component\HttpFoundation\Response;
use Tests\TestCase;

class EnsureBusinessSubscriptionActiveTest extends TestCase
{
    use RefreshDatabase;

    public function test_expired_business_is_blocked_from_write_requests(): void
    {
        $business = Business::factory()->create([
            'status' => 'active',
            'expires_at' => Carbon::now()->subDay(),
        ]);

        $user = User::factory()->create([
            'business_id' => $business->id,
        ]);

        $request = Request::create('/api/v1/products', 'POST');
        $request->setUserResolver(fn () => $user);

        $response = app(EnsureBusinessSubscriptionActive::class)->handle(
            $request,
            fn () => new Response('allowed')
        );

        $this->assertSame(403, $response->getStatusCode());
        $this->assertSame('SUBSCRIPTION_EXPIRED', $response->getData(true)['code']);
    }

    public function test_suspended_business_is_blocked_from_write_requests(): void
    {
        $business = Business::factory()->create([
            'status' => 'suspended',
            'expires_at' => Carbon::now()->addMonth(),
        ]);

        $user = User::factory()->create([
            'business_id' => $business->id,
        ]);

        $request = Request::create('/api/v1/products', 'POST');
        $request->setUserResolver(fn () => $user);

        $response = app(EnsureBusinessSubscriptionActive::class)->handle(
            $request,
            fn () => new Response('allowed')
        );

        $this->assertSame(403, $response->getStatusCode());
        $this->assertSame('BUSINESS_SUSPENDED', $response->getData(true)['code']);
    }

    public function test_expired_business_can_read_data(): void
    {
        $business = Business::factory()->create([
            'status' => 'active',
            'expires_at' => Carbon::now()->subDay(),
        ]);

        $user = User::factory()->create([
            'business_id' => $business->id,
        ]);

        $request = Request::create('/api/v1/products', 'GET');
        $request->setUserResolver(fn () => $user);

        $response = app(EnsureBusinessSubscriptionActive::class)->handle(
            $request,
            fn () => new Response('allowed')
        );

        $this->assertSame(200, $response->getStatusCode());
        $this->assertSame('allowed', $response->getContent());
    }

    public function test_active_business_can_write_data(): void
    {
        $business = Business::factory()->create([
            'status' => 'active',
            'expires_at' => Carbon::now()->addMonth(),
        ]);

        $user = User::factory()->create([
            'business_id' => $business->id,
        ]);

        $request = Request::create('/api/v1/products', 'POST');
        $request->setUserResolver(fn () => $user);

        $response = app(EnsureBusinessSubscriptionActive::class)->handle(
            $request,
            fn () => new Response('allowed')
        );

        $this->assertSame(200, $response->getStatusCode());
        $this->assertSame('allowed', $response->getContent());
    }

    public function test_trial_business_can_write_data(): void
    {
        $business = Business::factory()->create([
            'status' => 'trial',
            'expires_at' => null,
        ]);

        $user = User::factory()->create([
            'business_id' => $business->id,
        ]);

        $request = Request::create('/api/v1/products', 'POST');
        $request->setUserResolver(fn () => $user);

        $response = app(EnsureBusinessSubscriptionActive::class)->handle(
            $request,
            fn () => new Response('allowed')
        );

        $this->assertSame(200, $response->getStatusCode());
        $this->assertSame('allowed', $response->getContent());
    }
}