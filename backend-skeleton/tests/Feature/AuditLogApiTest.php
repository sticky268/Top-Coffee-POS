<?php

namespace Tests\Feature;

use App\Models\AuditLog;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Spatie\Permission\Models\Permission;
use Spatie\Permission\Models\Role;
use Tests\TestCase;

class AuditLogApiTest extends TestCase
{
    use RefreshDatabase;

    public function test_user_with_audit_view_permission_can_list_audit_logs(): void
    {
        $user = User::factory()->create([
            'is_active' => true,
        ]);

        $permission = Permission::findOrCreate('audit.view');
        $role = Role::findOrCreate('audit-viewer');
        $role->givePermissionTo($permission);
        $user->assignRole($role);

        AuditLog::create([
            'user_id' => $user->id,
            'action' => 'order.created',
            'auditable_type' => 'App\\Models\\Order',
            'auditable_id' => 101,
            'new_values' => [
                'total' => 10.00,
            ],
            'ip_address' => '127.0.0.1',
        ]);

        $response = $this->actingAs($user)->getJson('/api/v1/audit-logs');

        $response
            ->assertOk()
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.0.action', 'order.created')
            ->assertJsonPath('data.0.user.id', $user->id)
            ->assertJsonPath('data.0.user.name', $user->name)
            ->assertJsonPath('data.0.auditable_type', 'App\\Models\\Order')
            ->assertJsonPath('data.0.auditable_id', 101)
            ->assertJsonPath('data.0.new_values.total', 10)
            ->assertJsonPath('meta.current_page', 1)
            ->assertJsonPath('meta.total', 1);
    }

    public function test_user_without_audit_view_permission_is_forbidden(): void
    {
        $user = User::factory()->create([
            'is_active' => true,
        ]);

        $response = $this->actingAs($user)->getJson('/api/v1/audit-logs');

        $response
            ->assertForbidden()
            ->assertJson([
                'success' => false,
                'message' => 'You do not have permission to view audit logs',
            ]);
    }

    public function test_audit_log_filters_and_pagination_work(): void
    {
        $user = User::factory()->create([
            'is_active' => true,
        ]);

        $permission = Permission::findOrCreate('audit.view');
        $role = Role::findOrCreate('audit-filter-viewer');
        $role->givePermissionTo($permission);
        $user->assignRole($role);

        AuditLog::create([
            'user_id' => $user->id,
            'action' => 'order.created',
            'auditable_type' => 'App\\Models\\Order',
            'auditable_id' => 201,
            'ip_address' => '127.0.0.1',
        ]);

        AuditLog::create([
            'user_id' => $user->id,
            'action' => 'inventory.adjusted',
            'auditable_type' => 'App\\Models\\Ingredient',
            'auditable_id' => 301,
            'ip_address' => '127.0.0.1',
        ]);

        AuditLog::create([
            'user_id' => $user->id,
            'action' => 'order.updated',
            'auditable_type' => 'App\\Models\\Order',
            'auditable_id' => 202,
            'ip_address' => '127.0.0.1',
        ]);

        $response = $this->actingAs($user)->getJson(
            '/api/v1/audit-logs?action=order.created&per_page=1&page=1'
        );

        $response
            ->assertOk()
            ->assertJsonPath('success', true)
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.action', 'order.created')
            ->assertJsonPath('meta.current_page', 1)
            ->assertJsonPath('meta.last_page', 1)
            ->assertJsonPath('meta.per_page', 1)
            ->assertJsonPath('meta.total', 1);

        $response = $this->actingAs($user)->getJson(
            '/api/v1/audit-logs?search=inventory'
        );

        $response
            ->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.action', 'inventory.adjusted');
    }
}