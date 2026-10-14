<?php

namespace Tests\Feature;

use App\Models\{AuditLog, Branch, Business, Category, Customer, ExpenseCategory, Product, Supplier, User};
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Storage;
use Illuminate\Http\UploadedFile;
use Tests\TestCase;

class TenantDataIsolationTest extends TestCase
{
    use RefreshDatabase;

    private function image(): UploadedFile
    {
        return UploadedFile::fake()->createWithContent('coffee.png', base64_decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j/p8AAAAASUVORK5CYII='));
    }

    private function actors(): array
    {
        $this->seed(RolePermissionSeeder::class);
        $actors = [];
        foreach (['A', 'B'] as $name) {
            $business = Business::factory()->create();
            $branch = Branch::factory()->create(['business_id' => $business->id]);
            $admin = User::factory()->create(['business_id' => $business->id]);
            $admin->assignRole('admin');
            $admin->branches()->attach($branch->id, ['is_primary' => true]);
            $actors[] = [$admin, $branch];
        }
        return $actors;
    }

    public function test_foreign_category_product_recipe_and_customer_ids_are_not_accessible(): void
    {
        [[$a, $branchA], [$b, $branchB]] = $this->actors();
        $this->actingAs($b);
        $category = Category::create(['branch_id' => $branchB->id, 'name' => 'Private B']);
        $product = Product::create(['category_id' => $category->id, 'name' => 'Private B', 'base_price' => 10]);
        $customer = Customer::create(['branch_id' => $branchB->id, 'name' => 'Private B']);
        $this->actingAs($a);
        $this->patchJson('/api/v1/categories/'.$category->id, ['name' => 'Changed'])->assertNotFound();
        $this->deleteJson('/api/v1/categories/'.$category->id)->assertNotFound();
        $this->patchJson('/api/v1/products/'.$product->id, ['base_price' => 0])->assertNotFound();
        $this->getJson('/api/v1/products/'.$product->id.'/recipe')->assertNotFound();
        $this->putJson('/api/v1/products/'.$product->id.'/recipe', ['items' => []])->assertNotFound();
        foreach (['', '/orders', '/loyalty'] as $suffix) {
            $this->getJson('/api/v1/customers/'.$customer->id.$suffix)->assertNotFound();
        }
        $this->patchJson('/api/v1/customers/'.$customer->id, ['name' => 'Changed'])->assertNotFound();
        $this->postJson('/api/v1/customers/'.$customer->id.'/loyalty/adjust', ['points' => 10])->assertNotFound();
        $this->deleteJson('/api/v1/customers/'.$customer->id)->assertNotFound();
        $this->assertDatabaseHas('products', ['id' => $product->id, 'base_price' => 10]);
        $this->assertDatabaseHas('customers', ['id' => $customer->id, 'name' => 'Private B', 'deleted_at' => null]);
    }

    public function test_business_wide_customers_suppliers_and_categories_are_private(): void
    {
        [[$a, $branchA], [$b, $branchB]] = $this->actors();
        $this->actingAs($b);
        $customer = Customer::create(['name' => 'Private B', 'branch_id' => null]);
        Category::create(['name' => 'Private B', 'branch_id' => null]);
        $supplier = Supplier::create(['name' => 'Private B', 'branch_id' => null]);
        ExpenseCategory::create(['name' => 'Private B']);
        $this->actingAs($a);
        foreach (['customers', 'categories', 'suppliers', 'expense-categories'] as $endpoint) {
            $this->getJson('/api/v1/'.$endpoint)->assertOk()->assertJsonCount(0, 'data');
        }
        $this->getJson('/api/v1/customers/'.$customer->id)->assertNotFound();
        $this->patchJson('/api/v1/suppliers/'.$supplier->id, ['name' => 'Changed'])->assertNotFound();
        $this->deleteJson('/api/v1/suppliers/'.$supplier->id)->assertNotFound();
        $this->actingAs($b)->getJson('/api/v1/customers')->assertOk()->assertJsonCount(1, 'data');
    }

    public function test_audit_logs_and_staff_lists_do_not_expose_another_business(): void
    {
        [[$a], [$b]] = $this->actors();
        $this->actingAs($b);
        AuditLog::create(['user_id' => $b->id, 'action' => 'private.action', 'new_values' => ['private' => 'B']]);
        $this->actingAs($a)->getJson('/api/v1/audit-logs')->assertOk()->assertJsonCount(0, 'data');
        $this->getJson('/api/v1/users')->assertOk()->assertJsonCount(1, 'data')->assertJsonPath('data.0.id', $a->id);
        $this->getJson('/api/v1/users/'.$b->id)->assertForbidden();
    }

    public function test_foreign_category_cannot_be_attached_to_a_new_product(): void
    {
        [[$a], [$b, $branchB]] = $this->actors();
        $this->actingAs($b);
        $category = Category::create(['name' => 'Private B', 'branch_id' => $branchB->id]);
        $this->actingAs($a)->postJson('/api/v1/products', [
            'name' => 'Bad link', 'base_price' => 10, 'category_id' => $category->id,
        ])->assertForbidden();
        $this->assertDatabaseMissing('products', ['name' => 'Bad link']);
    }

    public function test_each_business_can_use_the_same_sku_and_cannot_replace_foreign_images(): void
    {
        Storage::fake('public');
        [[$a, $branchA], [$b, $branchB]] = $this->actors();
        $products = [];
        foreach ([[$a, $branchA], [$b, $branchB]] as [$actor, $branch]) {
            $this->actingAs($actor);
            $category = Category::create(['name' => 'Coffee', 'branch_id' => $branch->id]);
            $response = $this->postJson('/api/v1/products', [
                'name' => 'Coffee', 'category_id' => $category->id, 'base_price' => 10, 'sku' => 'COFFEE',
                'image' => $this->image(),
                'branches' => [['branch_id' => $branch->id, 'is_available' => true]],
            ])->assertCreated();
            $products[] = Product::findOrFail($response->json('data.id'));
        }
        $path = $products[1]->images()->firstOrFail()->path;
        $this->actingAs($a)->patchJson('/api/v1/products/'.$products[1]->id, [
            'image' => $this->image(),
        ])->assertNotFound();
        Storage::disk('public')->assertExists($path);
        $this->assertStringStartsWith('businesses/'.$b->business_id.'/products/', $path);
        $foreignVariant = \App\Models\ProductVariant::create(['product_id' => $products[1]->id, 'name' => 'Large', 'price_delta' => 2]);
        $this->patchJson('/api/v1/products/'.$products[0]->id, ['variants' => [
            ['id' => $foreignVariant->id, 'name' => 'Changed', 'price_delta' => 0],
        ]])->assertUnprocessable();
        $this->assertDatabaseHas('product_variants', ['id' => $foreignVariant->id, 'name' => 'Large', 'price_delta' => 2]);
        $this->assertDatabaseCount('product_variants', 1);
    }

    public function test_foreign_customer_supplier_and_expense_category_references_are_rejected_before_writes(): void
    {
        [[$a, $branchA], [$b, $branchB]] = $this->actors();
        $this->actingAs($b);
        $customer = Customer::create(['name' => 'Private customer', 'branch_id' => null]);
        $supplier = Supplier::create(['name' => 'Private supplier', 'branch_id' => null]);
        $category = ExpenseCategory::create(['name' => 'Private expenses']);
        $this->actingAs($a);
        $this->postJson('/api/v1/orders', ['customer_id' => $customer->id])->assertForbidden();
        $this->postJson('/api/v1/purchases', ['supplier_id' => $supplier->id])->assertForbidden();
        $this->postJson('/api/v1/expenses', ['category_id' => $category->id])->assertForbidden();
        $this->assertDatabaseCount('orders', 0);
        $this->assertDatabaseCount('payments', 0);
        $this->assertDatabaseCount('purchases', 0);
        $this->assertDatabaseCount('expenses', 0);
        $this->assertDatabaseCount('stock_movements', 0);
        $this->actingAs($b)->postJson('/api/v1/expenses', [
            'category_id' => $category->id, 'amount' => 5, 'spent_at' => now()->toDateString(),
        ])->assertCreated();
    }

    public function test_client_cannot_choose_business_owner_and_missing_owner_is_hidden(): void
    {
        [[$a, $branchA], [$b]] = $this->actors();
        $this->actingAs($a);
        $category = Category::create(['name' => 'Own category', 'branch_id' => $branchA->id]);
        $result = $this->postJson('/api/v1/products', ['name' => 'Own product', 'category_id' => $category->id,
            'base_price' => 10, 'business_id' => $b->business_id])->assertCreated();
        $this->assertDatabaseHas('products', ['id' => $result->json('data.id'), 'business_id' => $a->business_id]);
        $unknown = \Illuminate\Support\Facades\DB::table('customers')->insertGetId(['name' => 'Unresolved owner', 'branch_id' => null]);
        foreach ([$a, $b] as $actor) {
            $this->actingAs($actor)->getJson('/api/v1/customers/'.$unknown)->assertNotFound();
        }
        $this->assertFalse(app(\App\Services\TenantIntegrity::class)->report()['ready']);
    }

    public function test_invalid_business_and_branch_assignments_cannot_login_or_reuse_tokens(): void
    {
        [[$a], [$b, $branchB]] = $this->actors();
        $a->branches()->attach($branchB->id);
        $this->postJson('/api/v1/auth/login', ['email' => $a->email, 'password' => 'password', 'device_name' => 'test'])
            ->assertForbidden();
        $this->assertDatabaseCount('personal_access_tokens', 0);
        $token = $b->createToken('before-business-deactivation')->plainTextToken;
        $b->business->update(['is_active' => false]);
        Auth::forgetGuards();
        $this->withToken($token)->getJson('/api/v1/auth/me')->assertForbidden();
        $this->postJson('/api/v1/auth/login', ['email' => $b->email, 'password' => 'password', 'device_name' => 'test'])
            ->assertForbidden();
        $this->assertDatabaseCount('personal_access_tokens', 1);
    }
}
