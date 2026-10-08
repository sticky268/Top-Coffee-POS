<?php

namespace Tests\Feature;

use App\Models\Branch;
use App\Models\Business;
use App\Models\Expense;
use App\Models\ExpenseCategory;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Spatie\Permission\Models\Permission;
use Spatie\Permission\Models\Role;
use Tests\TestCase;

class ExpenseTest extends TestCase
{
    use RefreshDatabase;

    private Business $business;

    protected function setUp(): void
    {
        parent::setUp();

        $this->business = Business::factory()->create();
    }

    private function createBranch(string $name, string $code): Branch
    {
        return Branch::create([
            'business_id' => $this->business->id,
            'name' => $name,
            'code' => $code,
        ]);
    }

    private function makeUserForBranch(
        Branch $branch,
        string $role = 'manager'
    ): User {
        Role::firstOrCreate([
            'name' => $role,
            'guard_name' => 'web',
        ]);

        $user = User::factory()->create(['business_id' => $branch->business_id]);
        $user->assignRole($role);
        $user->branches()->attach($branch->id, ['is_primary' => true]);

        return $user;
    }

    private function seedExpensePermissions(): void
    {
        foreach (['expenses.manage', 'branches.view-all'] as $permission) {
            Permission::firstOrCreate([
                'name' => $permission,
                'guard_name' => 'web',
            ]);
        }

        $manager = Role::firstOrCreate([
            'name' => 'manager',
            'guard_name' => 'web',
        ]);
        $manager->syncPermissions(['expenses.manage']);

        $admin = Role::firstOrCreate([
            'name' => 'admin',
            'guard_name' => 'web',
        ]);
        $admin->syncPermissions([
            'expenses.manage',
            'branches.view-all',
        ]);

        Role::firstOrCreate([
            'name' => 'cashier',
            'guard_name' => 'web',
        ]);
    }

    private function makeExpense(
        Branch $branch,
        User $user,
        ExpenseCategory $category,
        array $overrides = []
    ): Expense {
        return Expense::create(array_merge([
            'branch_id' => $branch->id,
            'expense_category_id' => $category->id,
            'user_id' => $user->id,
            'amount' => 25.50,
            'description' => 'Coffee shop supplies',
            'spent_at' => '2026-09-20',
        ], $overrides));
    }

    public function test_unauthenticated_request_is_rejected(): void
    {
        $this->getJson('/api/v1/expenses')
            ->assertStatus(401);
    }

    public function test_user_without_expense_permission_cannot_view_expenses(): void
    {
        $branch = $this->createBranch('Riverside', 'PP-01');

        $user = $this->makeUserForBranch($branch, 'cashier');

        $response = $this->actingAs($user)
            ->getJson('/api/v1/expenses');

        $response->assertStatus(403)
            ->assertJsonPath('success', false);
    }

    public function test_manager_can_list_expenses_in_their_branch(): void
    {
        $this->seedExpensePermissions();

        $branch = $this->createBranch('Riverside', 'PP-01');

        $user = $this->makeUserForBranch($branch);
        $category = ExpenseCategory::create(['name' => 'Supplies']);

        $expense = $this->makeExpense($branch, $user, $category);

        $response = $this->actingAs($user)
            ->getJson('/api/v1/expenses');

        $response->assertStatus(200)
            ->assertJsonPath('success', true);

        $ids = collect($response->json('data'))
            ->pluck('id')
            ->all();

        $this->assertContains($expense->id, $ids);
    }

    public function test_manager_cannot_see_expenses_from_another_branch(): void
    {
        $this->seedExpensePermissions();

        $branch = $this->createBranch('Riverside', 'PP-01');

        $otherBranch = $this->createBranch('BKK1', 'PP-02');

        $user = $this->makeUserForBranch($branch);
        $otherUser = $this->makeUserForBranch($otherBranch);
        $category = ExpenseCategory::create(['name' => 'Supplies']);

        $otherExpense = $this->makeExpense(
            $otherBranch,
            $otherUser,
            $category
        );

        $response = $this->actingAs($user)
            ->getJson('/api/v1/expenses');

        $response->assertStatus(200);

        $ids = collect($response->json('data'))
            ->pluck('id')
            ->all();

        $this->assertNotContains($otherExpense->id, $ids);
    }

    public function test_manager_can_create_expense(): void
    {
        $this->seedExpensePermissions();

        $branch = $this->createBranch('Riverside', 'PP-01');

        $user = $this->makeUserForBranch($branch);
        $category = ExpenseCategory::create(['name' => 'Utilities']);

        $response = $this->actingAs($user)
            ->postJson('/api/v1/expenses', [
                'category_id' => $category->id,
                'amount' => 35.75,
                'description' => 'Electricity',
                'spent_at' => '2026-09-22 00:00:00',
            ]);

        $response->assertStatus(201)
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.amount', '35.75')
            ->assertJsonPath('data.description', 'Electricity');

        $this->assertDatabaseHas('expenses', [
            'branch_id' => $branch->id,
            'expense_category_id' => $category->id,
            'user_id' => $user->id,
            'amount' => 35.75,
            'description' => 'Electricity',
            'spent_at' => '2026-09-22 00:00:00',
        ]);
    }

    public function test_manager_can_view_one_expense(): void
    {
        $this->seedExpensePermissions();

        $branch = $this->createBranch('Riverside', 'PP-01');

        $user = $this->makeUserForBranch($branch);
        $category = ExpenseCategory::create(['name' => 'Supplies']);
        $expense = $this->makeExpense($branch, $user, $category);

        $response = $this->actingAs($user)
            ->getJson("/api/v1/expenses/{$expense->id}");

        $response->assertStatus(200)
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.id', $expense->id);
    }

    public function test_manager_can_update_expense(): void
    {
        $this->seedExpensePermissions();

        $branch = $this->createBranch('Riverside', 'PP-01');

        $user = $this->makeUserForBranch($branch);
        $category = ExpenseCategory::create(['name' => 'Supplies']);
        $expense = $this->makeExpense($branch, $user, $category);

        $response = $this->actingAs($user)
            ->patchJson("/api/v1/expenses/{$expense->id}", [
                'amount' => 50.00,
                'description' => 'Updated supplies',
            ]);

        $response->assertStatus(200)
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.amount', '50.00')
            ->assertJsonPath('data.description', 'Updated supplies');

        $this->assertDatabaseHas('expenses', [
            'id' => $expense->id,
            'amount' => 50.00,
            'description' => 'Updated supplies',
        ]);
    }

    public function test_manager_cannot_update_expense_in_another_branch(): void
    {
        $this->seedExpensePermissions();

        $branch = $this->createBranch('Riverside', 'PP-01');

        $otherBranch = $this->createBranch('BKK1', 'PP-02');

        $user = $this->makeUserForBranch($branch);
        $otherUser = $this->makeUserForBranch($otherBranch);
        $category = ExpenseCategory::create(['name' => 'Supplies']);

        $expense = $this->makeExpense(
            $otherBranch,
            $otherUser,
            $category
        );

        $response = $this->actingAs($user)
            ->patchJson("/api/v1/expenses/{$expense->id}", [
                'amount' => 999.00,
            ]);

        $response->assertStatus(404);

        $this->assertDatabaseHas('expenses', [
            'id' => $expense->id,
            'amount' => 25.50,
        ]);
    }

    public function test_admin_can_access_another_branch(): void
    {
        $this->seedExpensePermissions();

        $branch = $this->createBranch('Riverside', 'PP-01');

        $otherBranch = $this->createBranch('BKK1', 'PP-02');

        $admin = $this->makeUserForBranch($branch, 'admin');
        $otherUser = $this->makeUserForBranch($otherBranch);
        $category = ExpenseCategory::create(['name' => 'Supplies']);

        $expense = $this->makeExpense(
            $otherBranch,
            $otherUser,
            $category
        );

        $response = $this->actingAs($admin)
            ->getJson("/api/v1/expenses?branch_id={$otherBranch->id}");

        $response->assertStatus(200)
            ->assertJsonPath('success', true);

        $ids = collect($response->json('data'))
            ->pluck('id')
            ->all();

        $this->assertContains($expense->id, $ids);
    }

    public function test_expense_validation_rejects_invalid_data(): void
    {
        $this->seedExpensePermissions();

        $branch = $this->createBranch('Riverside', 'PP-01');

        $user = $this->makeUserForBranch($branch);

        $response = $this->actingAs($user)
            ->postJson('/api/v1/expenses', [
                'category_id' => 999999,
                'amount' => 0,
                'spent_at' => 'not-a-date',
            ]);

        $response->assertStatus(422)
            ->assertJsonPath('success', false);
    }

    public function test_user_without_assigned_branch_gets_clear_error(): void
    {
        $this->seedExpensePermissions();

        $user = User::factory()->create();
        $user->assignRole('manager');

        $response = $this->actingAs($user)
            ->getJson('/api/v1/expenses');

        $response->assertStatus(422)
            ->assertJsonPath('success', false);
    }

    public function test_nonexistent_expense_returns_not_found(): void
    {
        $this->seedExpensePermissions();

        $branch = $this->createBranch('Riverside', 'PP-01');

        $user = $this->makeUserForBranch($branch);

        $response = $this->actingAs($user)
            ->getJson('/api/v1/expenses/999999');

        $response->assertStatus(404);
    }
    public function test_manager_can_view_expense_summary(): void
    {
        $this->seedExpensePermissions();

        $branch = $this->createBranch('Riverside', 'PP-01');

        $user = $this->makeUserForBranch($branch);

        $supplies = ExpenseCategory::create([
            'name' => 'Supplies',
        ]);

        $utilities = ExpenseCategory::create([
            'name' => 'Utilities',
        ]);

        $this->travelTo(\Carbon\Carbon::create(2026, 9, 23, 12, 0, 0));

        $today = now()->toDateString();
        $yesterday = now()->subDay()->toDateString();

        $this->makeExpense($branch, $user, $supplies, [
            'amount' => 40.00,
            'spent_at' => $today,
        ]);

        $this->makeExpense($branch, $user, $utilities, [
            'amount' => 25.00,
            'spent_at' => $today,
        ]);

        $this->makeExpense($branch, $user, $supplies, [
            'amount' => 15.00,
            'spent_at' => $yesterday,
        ]);

        $response = $this->actingAs($user)
            ->getJson('/api/v1/expenses/summary');

        $response->assertStatus(200)
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.today', 65)
            ->assertJsonPath('data.week', 80)
            ->assertJsonPath('data.month', 80);

        $categories = collect($response->json('data.categories'))
            ->keyBy('category_name');

        $this->assertSame(55.0, (float) $categories['Supplies']['amount']);
        $this->assertSame(25.0, (float) $categories['Utilities']['amount']);

        $trend = collect($response->json('data.trend'));

        $this->assertCount(7, $trend);
        $this->assertSame($today, $trend->last()['date']);
        $this->assertSame(65.0, (float) $trend->last()['amount']);
    }

    public function test_expense_summary_combines_multiple_expenses_on_the_same_day(): void
    {
        $this->seedExpensePermissions();

        $branch = $this->createBranch('Riverside', 'PP-01');
        $user = $this->makeUserForBranch($branch);
        $category = ExpenseCategory::create([
            'name' => 'Supplies',
        ]);

        $this->travelTo(\Carbon\Carbon::create(2026, 9, 23, 12, 0, 0));

        $this->makeExpense($branch, $user, $category, [
            'amount' => 40.00,
            'spent_at' => '2026-09-23 09:00:00',
        ]);

        $this->makeExpense($branch, $user, $category, [
            'amount' => 25.00,
            'spent_at' => '2026-09-23 15:00:00',
        ]);

        $response = $this->actingAs($user)
            ->getJson('/api/v1/expenses/summary');

        $response->assertStatus(200)
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.today', 65);

        $trend = collect($response->json('data.trend'));

        $this->assertSame(65.0, (float) $trend->last()['amount']);
    }
    public function test_expense_summary_is_scoped_to_the_selected_branch(): void
    {
        $this->seedExpensePermissions();

        $branch = $this->createBranch('Riverside', 'PP-01');

        $otherBranch = $this->createBranch('BKK1', 'PP-02');

        $user = $this->makeUserForBranch($branch);
        $otherUser = $this->makeUserForBranch($otherBranch);

        $category = ExpenseCategory::create([
            'name' => 'Supplies',
        ]);

        $this->makeExpense($branch, $user, $category, [
            'amount' => 30.00,
            'spent_at' => now()->toDateString(),
        ]);

        $this->makeExpense($otherBranch, $otherUser, $category, [
            'amount' => 999.00,
            'spent_at' => now()->toDateString(),
        ]);

        $response = $this->actingAs($user)
            ->getJson('/api/v1/expenses/summary');

        $response->assertStatus(200)
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.today', 30)
            ->assertJsonPath('data.week', 30)
            ->assertJsonPath('data.month', 30);
    }

    public function test_user_without_expense_permission_cannot_view_expense_summary(): void
    {
        $this->seedExpensePermissions();

        $branch = $this->createBranch('Riverside', 'PP-01');

        $user = $this->makeUserForBranch($branch, 'cashier');

        $response = $this->actingAs($user)
            ->getJson('/api/v1/expenses/summary');

        $response->assertStatus(403)
            ->assertJsonPath('success', false);
    }
}
