<?php

namespace Tests\Feature;

use Database\Seeders\DatabaseSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class DemoLoginSetupTest extends TestCase
{
    use RefreshDatabase;

    public function test_fresh_demo_installation_seeds_and_admin_can_sign_in(): void
    {
        config(['app.env' => 'local']);
        $this->seed(DatabaseSeeder::class);

        $this->assertDatabaseMissing('users', ['email' => 'kitchen@topcoffee.test']);
        $this->postJson('/api/v1/auth/login', [
            'email' => 'admin@topcoffee.test',
            'password' => 'password',
            'device_name' => 'Disposable Windows test',
        ])->assertOk()
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.user.roles.0', 'admin');
    }
}
