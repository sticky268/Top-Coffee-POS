<?php

namespace Tests\Feature;

use App\Models\Branch;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Spatie\Permission\Models\Role;
use Tests\TestCase;

class AuthTest extends TestCase
{
    use RefreshDatabase;

    public function test_active_user_can_login_with_correct_credentials(): void
    {
        Role::firstOrCreate(['name' => 'cashier', 'guard_name' => 'web']);

        $branch = Branch::factory()->create();
        $user = User::factory()->create(['password' => bcrypt('password'), 'is_active' => true]);
        $user->assignRole('cashier');
        $user->branches()->attach($branch->id, ['is_primary' => true]);

        $response = $this->postJson('/api/v1/auth/login', [
            'email' => $user->email,
            'password' => 'password',
            'device_name' => 'phpunit-test',
        ]);

        $response->assertStatus(200)
            ->assertJsonPath('success', true)
            ->assertJsonStructure(['data' => ['token', 'user' => ['id', 'email', 'roles', 'permissions', 'branches']]]);
    }

    public function test_login_fails_with_wrong_password(): void
    {
        $user = User::factory()->create(['password' => bcrypt('password')]);

        $response = $this->postJson('/api/v1/auth/login', [
            'email' => $user->email,
            'password' => 'wrong-password',
            'device_name' => 'phpunit-test',
        ]);

        $response->assertStatus(401)->assertJsonPath('success', false);
    }

    public function test_deactivated_user_cannot_login(): void
    {
        $user = User::factory()->create(['password' => bcrypt('password'), 'is_active' => false]);

        $response = $this->postJson('/api/v1/auth/login', [
            'email' => $user->email,
            'password' => 'password',
            'device_name' => 'phpunit-test',
        ]);

        $response->assertStatus(403)->assertJsonPath('success', false);
    }

    public function test_authenticated_user_can_fetch_own_profile(): void
    {
        $user = User::factory()->create();
        $token = $user->createToken('test')->plainTextToken;

        $response = $this->withHeader('Authorization', "Bearer {$token}")
            ->getJson('/api/v1/auth/me');

        $response->assertStatus(200)->assertJsonPath('data.email', $user->email);
    }

    public function test_unauthenticated_request_is_rejected(): void
    {
        $this->getJson('/api/v1/auth/me')->assertStatus(401);
    }
}
