<?php

namespace Tests\Feature;

use App\Models\{Branch, User};
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Cache;
use Tests\TestCase;

class LoginLockoutTest extends TestCase
{
    use RefreshDatabase;

    private User $user;

    protected function setUp(): void
    {
        parent::setUp();
        Cache::flush();
        $branch = Branch::factory()->create();
        $this->user = User::factory()->create([
            'business_id' => $branch->business_id,
            'email' => 'cashier@example.test', 'password' => bcrypt('correct-password'),
            'is_active' => true,
        ]);
        $this->user->branches()->attach($branch->id);
    }

    private function login(string $password = 'wrong-password', ?string $email = null)
    {
        return $this->postJson('/api/v1/auth/login', [
            'email' => $email ?? $this->user->email,
            'password' => $password, 'device_name' => 'lockout-test',
        ]);
    }

    private function lockAccount(): void
    {
        for ($i = 0; $i < 4; $i++) $this->login()->assertUnauthorized();
        $this->login()->assertTooManyRequests()
            ->assertJsonPath('code', 'LOGIN_LOCKED')
            ->assertJsonPath('retry_after', 900)->assertHeader('Retry-After', '900');
    }

    public function test_fifth_failure_locks_even_correct_credentials_without_creating_a_token(): void
    {
        $this->lockAccount();
        $this->withServerVariables(['REMOTE_ADDR' => '192.0.2.20']);
        $this->login('correct-password')->assertTooManyRequests()
            ->assertJsonPath('code', 'LOGIN_LOCKED');
        $this->assertDatabaseCount('personal_access_tokens', 0);
        $this->assertDatabaseCount('audit_logs', 5);
    }

    public function test_cooldown_starts_at_fifth_failure_and_retries_do_not_extend_it(): void
    {
        for ($i = 0; $i < 4; $i++) $this->login()->assertUnauthorized();
        $this->travel(14)->minutes();
        $this->login()->assertTooManyRequests()->assertJsonPath('retry_after', 900);
        $this->travel(899)->seconds();
        $this->login('correct-password')->assertTooManyRequests()
            ->assertJsonPath('retry_after', 1)->assertHeader('Retry-After', '1');
        $this->travel(1)->seconds();
        $this->login('correct-password')->assertOk();
        $this->assertDatabaseCount('personal_access_tokens', 1);
    }

    public function test_successful_login_resets_previous_failures(): void
    {
        for ($i = 0; $i < 3; $i++) $this->login()->assertUnauthorized();
        $this->login('correct-password')->assertOk();
        for ($i = 0; $i < 4; $i++) $this->login()->assertUnauthorized();
        $this->login()->assertTooManyRequests()->assertJsonPath('code', 'LOGIN_LOCKED');
    }

    public function test_old_failures_expire_after_fifteen_minutes_of_inactivity(): void
    {
        for ($i = 0; $i < 4; $i++) $this->login()->assertUnauthorized();
        $this->travel(901)->seconds();
        $this->login()->assertUnauthorized();
    }

    public function test_case_and_whitespace_and_ip_changes_cannot_bypass_account_lockout(): void
    {
        for ($i = 0; $i < 4; $i++) {
            $this->withServerVariables(['REMOTE_ADDR' => '192.0.2.'.($i + 1)]);
            $this->login()->assertUnauthorized();
        }
        $this->withServerVariables(['REMOTE_ADDR' => '192.0.2.5']);
        $this->login('wrong-password', strtoupper($this->user->email))
            ->assertTooManyRequests()->assertJsonPath('code', 'LOGIN_LOCKED');
        $this->withServerVariables(['REMOTE_ADDR' => '192.0.2.6']);
        $this->login('correct-password', ' '.$this->user->email.' ')
            ->assertTooManyRequests()->assertJsonPath('code', 'LOGIN_LOCKED');
    }

    public function test_unknown_accounts_receive_the_same_cooldown_and_do_not_lock_other_accounts(): void
    {
        for ($i = 0; $i < 4; $i++) $this->login('wrong-password', 'missing@example.test')->assertUnauthorized();
        $this->login('wrong-password', 'missing@example.test')->assertTooManyRequests()
            ->assertJsonPath('code', 'LOGIN_LOCKED')->assertJsonPath('retry_after', 900);
        $this->login('correct-password')->assertOk();
    }

    public function test_invalid_payloads_do_not_count_as_failed_passwords_but_request_throttle_remains(): void
    {
        for ($i = 0; $i < 10; $i++) {
            $this->postJson('/api/v1/auth/login', ['email' => $this->user->email])
                ->assertUnprocessable();
        }
        $this->login()->assertTooManyRequests()->assertJsonPath('code', 'LOGIN_RATE_LIMITED');
        $this->travel(61)->seconds();
        for ($i = 0; $i < 4; $i++) $this->login()->assertUnauthorized();
    }

    public function test_database_cache_keeps_lockout_when_cache_connection_is_recreated(): void
    {
        config(['cache.default' => 'database']);
        $this->lockAccount();
        Cache::purge('database');
        $this->login('correct-password')->assertTooManyRequests()
            ->assertJsonPath('code', 'LOGIN_LOCKED');
        $this->assertDatabaseCount('personal_access_tokens', 0);
    }
}
