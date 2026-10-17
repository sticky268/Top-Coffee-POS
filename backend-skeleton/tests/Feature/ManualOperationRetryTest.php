<?php

namespace Tests\Feature;

use App\Models\{Branch, Business, ExpenseCategory, Ingredient, Unit, User};
use App\Services\StockMovementService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Spatie\Permission\Models\Permission;
use Tests\TestCase;

class ManualOperationRetryTest extends TestCase
{
    use RefreshDatabase;

    private Branch $branch;
    private User $actor;
    private Ingredient $ingredient;

    protected function setUp(): void
    {
        parent::setUp();
        $business = Business::factory()->create();
        $this->branch = Branch::create(['business_id' => $business->id, 'name' => 'Cafe', 'code' => 'MR-01']);
        $this->actor = User::factory()->create(['business_id' => $business->id]);
        $this->actor->branches()->attach($this->branch->id);
        foreach (['inventory.adjust', 'inventory.manage', 'expenses.manage', 'loyalty.manage', 'branches.view-all'] as $name) {
            Permission::firstOrCreate(['name' => $name, 'guard_name' => 'web']);
            $this->actor->givePermissionTo($name);
        }
        $this->actingAs($this->actor);
        $unit = Unit::create(['name' => 'Gram', 'abbreviation' => 'g', 'conversion_factor' => 1]);
        $this->ingredient = Ingredient::create(['branch_id' => $this->branch->id, 'unit_id' => $unit->id,
            'name' => 'Coffee', 'reorder_threshold' => 0, 'is_active' => true]);
        app(StockMovementService::class)->record($this->ingredient, 'purchase', 10, $this->actor->id);
    }

    private function payload(array $values): array
    {
        return $values + ['uuid' => (string) Str::uuid(), 'branch_id' => $this->branch->id,
            'expected_user_id' => $this->actor->id];
    }

    public function test_manual_stock_retry_records_one_movement_and_rejects_changed_details(): void
    {
        $path = '/api/v1/ingredients/'.$this->ingredient->id.'/movements';
        $payload = $this->payload(['type' => 'adjustment', 'quantity' => 2, 'reason' => 'Count correction']);
        $id = $this->postJson($path, $payload)->assertCreated()->json('data.movement.id');
        $this->postJson($path, $payload)->assertCreated()->assertJsonPath('data.movement.id', $id);
        $this->postJson($path, array_replace($payload, ['quantity' => 3]))->assertConflict();

        $this->assertSame(12.0, (float) $this->ingredient->fresh()->current_stock);
        $this->assertDatabaseCount('stock_movements', 2);
        $this->assertDatabaseCount('operation_requests', 1);
    }

    public function test_rejected_stock_adjustment_leaves_no_saved_success_or_partial_movement(): void
    {
        $this->postJson('/api/v1/ingredients/'.$this->ingredient->id.'/movements',
            $this->payload(['type' => 'adjustment', 'quantity' => -20, 'reason' => 'Invalid count']))
            ->assertUnprocessable();
        $this->assertSame(10.0, (float) $this->ingredient->fresh()->current_stock);
        $this->assertDatabaseCount('stock_movements', 1);
        $this->assertDatabaseCount('operation_requests', 0);
    }

    public function test_stock_request_cannot_change_its_branch_or_original_operator(): void
    {
        $path = '/api/v1/ingredients/'.$this->ingredient->id.'/movements';
        $payload = $this->payload(['type' => 'adjustment', 'quantity' => 2, 'reason' => 'Correction']);
        $this->postJson($path, array_replace($payload, ['branch_id' => $this->branch->id + 100]))->assertNotFound();
        $this->postJson($path, array_replace($payload, ['expected_user_id' => $this->actor->id + 100]))->assertForbidden();
        $this->assertDatabaseCount('stock_movements', 1);
        $this->assertDatabaseCount('operation_requests', 0);
    }

    public function test_expense_retry_creates_one_expense_in_the_requested_branch(): void
    {
        $branch = Branch::create(['business_id' => $this->actor->business_id, 'name' => 'Second Cafe', 'code' => 'MR-02']);
        $this->actor->branches()->attach($branch->id);
        $category = ExpenseCategory::forceCreate(['business_id' => $this->actor->business_id, 'name' => 'Supplies']);
        $payload = array_replace($this->payload(['category_id' => $category->id, 'amount' => 12.50,
            'description' => 'Supplies', 'spent_at' => '2026-10-17']), ['branch_id' => $branch->id]);
        $id = $this->postJson('/api/v1/expenses', $payload)->assertCreated()->json('data.id');
        $this->postJson('/api/v1/expenses', $payload)->assertCreated()->assertJsonPath('data.id', $id);
        $this->postJson('/api/v1/expenses', array_replace($payload, ['amount' => 15]))->assertConflict();
        $this->assertDatabaseHas('expenses', ['id' => $id, 'branch_id' => $branch->id, 'amount' => 12.50]);
        $this->assertDatabaseCount('expenses', 1);
        $this->assertDatabaseCount('operation_requests', 1);
    }

    public function test_invalid_branch_ids_are_rejected_before_settings_or_ingredient_writes(): void
    {
        foreach ([0, 999999, 'not-a-branch'] as $branchId) {
            $this->getJson('/api/v1/loyalty/settings?branch_id='.$branchId)->assertUnprocessable();
            $this->patchJson('/api/v1/loyalty/settings', ['branch_id' => $branchId, 'is_enabled' => true])
                ->assertUnprocessable();
            $this->postJson('/api/v1/ingredients', ['branch_id' => $branchId,
                'name' => 'Invalid', 'unit_id' => $this->ingredient->unit_id])->assertUnprocessable();
        }
        $this->assertDatabaseCount('loyalty_settings', 0);
        $this->assertDatabaseCount('ingredients', 1);
    }
}
