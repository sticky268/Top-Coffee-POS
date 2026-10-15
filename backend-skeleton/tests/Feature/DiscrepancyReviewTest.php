<?php
namespace Tests\Feature;

use App\Models\{Branch, Business, CashierShift, User};
use Illuminate\Foundation\Testing\RefreshDatabase;
use Spatie\Permission\Models\Permission;
use Tests\TestCase;

class DiscrepancyReviewTest extends TestCase
{
    use RefreshDatabase;

    public function test_branch_scoped_cash_variances_link_to_source_shifts(): void
    {
        $business = Business::factory()->create();
        $branch = Branch::factory()->create(['business_id' => $business->id, 'timezone' => 'UTC']);
        $other = Branch::factory()->create(['business_id' => $business->id]);
        $actor = User::factory()->create(['business_id' => $business->id]);
        $actor->branches()->attach($branch->id);
        foreach (['orders.view', 'reports.view'] as $name) {
            Permission::firstOrCreate(['name' => $name, 'guard_name' => 'web']);
            $actor->givePermissionTo($name);
        }
        $shift = CashierShift::create([
            'branch_id' => $branch->id, 'user_id' => $actor->id,
            'status' => 'closed', 'opening_cash' => 10,
            'expected_cash' => 10, 'counted_cash' => 8,
            'difference' => -2, 'closed_at' => now(),
        ]);
        CashierShift::create([
            'branch_id' => $other->id, 'user_id' => $actor->id,
            'status' => 'closed', 'opening_cash' => 10,
            'difference' => 7, 'closed_at' => now(),
        ]);
        $this->actingAs($actor)->getJson("/api/v1/dashboard?branch_id={$branch->id}")
            ->assertOk()
            ->assertJsonPath('data.stats.cash_discrepancy_count', 1)
            ->assertJsonPath('data.stats.cash_discrepancy_shift_id', $shift->id);
        $day = now()->utc()->format('Y-m-d');
        $this->getJson("/api/v1/reports/operations?branch_id={$branch->id}&date_from={$day}&date_to={$day}")
            ->assertOk()
            ->assertJsonPath('data.cash_difference_shift_count', 1)
            ->assertJsonPath('data.cash_difference_shifts.0.id', $shift->id);
        $this->getJson("/api/v1/shifts?branch_id={$branch->id}&shift_id={$shift->id}")
            ->assertOk()->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.id', $shift->id);
        $this->getJson("/api/v1/shifts?branch_id={$other->id}&shift_id={$shift->id}")
            ->assertForbidden();
        $actor->revokePermissionTo('reports.view');
        $this->getJson("/api/v1/dashboard?branch_id={$branch->id}")
            ->assertOk()->assertJsonPath('data.stats.cash_discrepancy_count', 0);
    }
}
