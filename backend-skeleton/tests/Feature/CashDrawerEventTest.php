<?php

namespace Tests\Feature;

use App\Models\{AuditLog, Branch, Business, Order, Payment, User};
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Spatie\Permission\Models\Permission;
use Tests\TestCase;

class CashDrawerEventTest extends TestCase
{
    use RefreshDatabase;

    private User $cashier;
    private Branch $branch;

    protected function setUp(): void
    {
        parent::setUp();
        $business = Business::factory()->create();
        $this->branch = Branch::factory()->create(['business_id' => $business->id]);
        $this->cashier = User::factory()->create(['business_id' => $business->id]);
        $this->cashier->branches()->attach($this->branch);
        $this->cashier->givePermissionTo(Permission::findOrCreate('orders.create'));
        $this->actingAs($this->cashier);
    }

    private function event(array $values = []): array
    {
        return $values + [
            'event_uuid' => (string) Str::uuid(),
            'branch_id' => $this->branch->id,
            'expected_user_id' => $this->cashier->id,
            'source' => 'manual',
            'reason' => 'Make change',
            'status' => 'attempt_recorded',
            'device_requested_at' => '2026-10-15T03:00:00.000Z',
        ];
    }

    private function cashOrder(string $method = 'cash', string $status = 'completed'): Order
    {
        $order = Order::create([
            'uuid' => (string) Str::uuid(), 'branch_id' => $this->branch->id,
            'user_id' => $this->cashier->id, 'order_type' => 'takeaway',
            'status' => $status, 'subtotal' => 5, 'total' => 5,
        ]);
        Payment::create([
            'order_id' => $order->id, 'method' => $method, 'amount' => 5,
            'status' => 'completed', 'processed_by' => $this->cashier->id,
        ]);
        return $order;
    }

    public function test_retries_record_one_request_and_a_monotonic_command_result(): void
    {
        $input = $this->event();
        $this->postJson('/api/v1/cash-drawer-events', $input)->assertOk()
            ->assertJsonPath('data.physical_open_confirmed', false);
        $this->postJson('/api/v1/cash-drawer-events', $input)->assertOk();
        $this->assertDatabaseCount('cash_drawer_events', 1);
        $this->assertDatabaseCount('audit_logs', 1);

        $sent = $input + ['device_finished_at' => '2026-10-15T03:00:01.000Z'];
        $sent['status'] = 'command_sent';
        $this->postJson('/api/v1/cash-drawer-events', $sent)->assertOk();
        $this->postJson('/api/v1/cash-drawer-events', $sent)->assertOk();
        $this->postJson('/api/v1/cash-drawer-events', $input)->assertOk()
            ->assertJsonPath('data.status', 'command_sent');
        $this->assertDatabaseCount('audit_logs', 2);
        $this->assertDatabaseHas('cash_drawer_events', [
            'business_id' => $this->cashier->business_id, 'branch_id' => $this->branch->id,
            'user_id' => $this->cashier->id, 'reason' => 'Make change', 'status' => 'command_sent',
        ]);
        $log = AuditLog::where('action', 'cash_drawer.command_sent')->firstOrFail();
        $this->assertFalse($log->new_values['physical_open_confirmed']);
        $this->assertSame('device_reported_command_only', $log->new_values['evidence']);
        $this->assertDatabaseCount('orders', 0);
        $this->assertDatabaseCount('payments', 0);
        $this->assertDatabaseCount('stock_movements', 0);
        $this->assertDatabaseCount('cash_movements', 0);
    }

    public function test_conflicting_reference_or_revised_final_result_is_rejected(): void
    {
        $input = $this->event([
            'status' => 'unconfirmed', 'device_finished_at' => '2026-10-15T03:00:01Z',
        ]);
        $this->postJson('/api/v1/cash-drawer-events', $input)->assertOk();
        $this->postJson('/api/v1/cash-drawer-events', array_replace($input, ['reason' => 'Different reason']))
            ->assertConflict();
        $this->postJson('/api/v1/cash-drawer-events', array_replace($input, ['status' => 'command_sent']))
            ->assertConflict();
        $this->assertDatabaseCount('cash_drawer_events', 1);
        $this->assertDatabaseCount('audit_logs', 1);
    }

    public function test_permission_assignment_tenant_and_original_actor_are_enforced(): void
    {
        $unassigned = Branch::factory()->create(['business_id' => $this->cashier->business_id]);
        $foreign = Branch::factory()->create(['business_id' => Business::factory()->create()->id]);
        $this->postJson('/api/v1/cash-drawer-events', $this->event(['branch_id' => $unassigned->id]))->assertForbidden();
        $this->postJson('/api/v1/cash-drawer-events', $this->event(['branch_id' => $foreign->id]))->assertNotFound();
        $this->postJson('/api/v1/cash-drawer-events', $this->event(['expected_user_id' => $this->cashier->id + 100]))->assertForbidden();
        $this->cashier->revokePermissionTo('orders.create');
        $this->postJson('/api/v1/cash-drawer-events', $this->event())->assertForbidden();
        $this->assertDatabaseCount('cash_drawer_events', 0);
        $this->assertDatabaseCount('audit_logs', 0);
    }

    public function test_manual_reason_and_server_owned_actor_fields_are_validated(): void
    {
        foreach ([
            ['reason' => '  '], ['reason' => str_repeat('x', 256)],
            ['physical_open_confirmed' => true], ['user_id' => $this->cashier->id],
            ['business_id' => $this->cashier->business_id],
            ['status' => 'opened'], ['status' => 'command_sent'],
        ] as $values) {
            $this->postJson('/api/v1/cash-drawer-events', $this->event($values))->assertUnprocessable();
        }
        $this->assertDatabaseCount('cash_drawer_events', 0);
    }

    public function test_automatic_event_requires_a_real_cash_payment_by_the_original_actor(): void
    {
        $cash = $this->cashOrder();
        $card = $this->cashOrder('card');
        $held = $this->cashOrder('cash', 'held');
        $automatic = ['source' => 'cash_sale', 'reason' => 'Completed cash sale'];
        $this->postJson('/api/v1/cash-drawer-events', $this->event($automatic + ['order_id' => $card->id]))
            ->assertUnprocessable();
        $this->postJson('/api/v1/cash-drawer-events', $this->event($automatic + ['order_id' => $held->id]))
            ->assertNotFound();
        DB::table('payments')->where('order_id', $cash->id)->update([
            'processed_by' => User::factory()->create(['business_id' => $this->cashier->business_id])->id,
        ]);
        $this->postJson('/api/v1/cash-drawer-events', $this->event($automatic + ['order_id' => $cash->id]))
            ->assertUnprocessable();
        $this->assertDatabaseCount('cash_drawer_events', 0);
    }

    public function test_delayed_cash_evidence_survives_refund_and_is_linked_to_the_sale(): void
    {
        $cash = $this->cashOrder();
        DB::table('payments')->where('order_id', $cash->id)->update(['status' => 'refunded']);
        $this->postJson('/api/v1/cash-drawer-events', $this->event([
            'source' => 'cash_sale', 'order_id' => $cash->id,
            'status' => 'command_sent', 'device_finished_at' => '2026-10-15T03:00:01Z',
        ]))->assertOk()->assertJsonPath('data.physical_open_confirmed', false);
        $this->assertDatabaseHas('cash_drawer_events', [
            'order_id' => $cash->id, 'source' => 'cash_sale', 'reason' => 'Completed cash sale',
        ]);
        $this->assertDatabaseCount('payments', 1);
        $this->assertDatabaseHas('payments', ['order_id' => $cash->id, 'status' => 'refunded']);
    }
}
