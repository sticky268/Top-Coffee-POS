<?php

namespace Tests\Feature;

use App\Models\AuditLog;
use App\Models\Branch;
use App\Models\Business;
use App\Models\User;
use App\Services\AuditLogService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class AuditLogTest extends TestCase
{
    use RefreshDatabase;

    public function test_audit_log_service_records_an_authenticated_action(): void
    {
        $business = Business::factory()->create();

        $branch = Branch::create([
            'business_id' => $business->id,
            'name' => 'Riverside',
            'code' => 'PP-01',
        ]);

        $user = User::factory()->create([
            'business_id' => $business->id,
            'is_active' => true,
        ]);

        $user->branches()->attach($branch->id, [
            'is_primary' => true,
        ]);

        $response = $this->actingAs($user)->getJson('/api/v1/users');

        $service = app(AuditLogService::class);

        $log = $service->record(
            request(),
            'user.tested',
            $user,
            ['name' => 'Old Name'],
            ['name' => 'New Name'],
        );

        $this->assertInstanceOf(AuditLog::class, $log);

        $this->assertDatabaseHas('audit_logs', [
            'id' => $log->id,
            'user_id' => $user->id,
            'action' => 'user.tested',
            'auditable_type' => $user->getMorphClass(),
            'auditable_id' => $user->id,
        ]);

        $this->assertSame(['name' => 'Old Name'], $log->old_values);
        $this->assertSame(['name' => 'New Name'], $log->new_values);
    }
}