<?php

namespace Tests\Feature;

use App\Models\{Branch, Business};
use App\Services\TenantIntegrity;
use Illuminate\Foundation\Testing\RefreshDatabaseState;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

class BusinessOwnershipMigrationTest extends TestCase
{
    private function legacySchema(): void
    {
        $paths = array_values(array_filter(glob(database_path('migrations/*.php')), fn ($path) => ! str_contains($path, 'add_business_ownership')));
        $this->artisan('migrate:fresh', ['--path' => $paths, '--realpath' => true])->assertExitCode(0);
    }

    protected function tearDown(): void
    {
        RefreshDatabaseState::$migrated = false;
        parent::tearDown();
    }

    private function migrateOwnership(): void
    {
        (require database_path('migrations/2026_10_08_000001_add_business_ownership.php'))->up();
    }

    public function test_single_business_backfill_preserves_existing_values_and_assigns_globals(): void
    {
        $this->legacySchema();
        $business = DB::table('businesses')->value('id');
        $category = DB::table('categories')->insertGetId(['name' => 'Coffee', 'branch_id' => null]);
        $product = DB::table('products')->insertGetId(['category_id' => $category, 'name' => 'Coffee', 'base_price' => 3.5, 'sku' => 'COFFEE']);
        $customer = DB::table('customers')->insertGetId(['name' => 'Customer', 'phone' => 'fixture', 'branch_id' => null]);
        $supplier = DB::table('suppliers')->insertGetId(['name' => 'Supplier', 'branch_id' => null]);
        $expense = DB::table('expense_categories')->insertGetId(['name' => 'Rent']);
        $this->migrateOwnership();
        foreach (['categories' => $category, 'products' => $product, 'customers' => $customer, 'suppliers' => $supplier, 'expense_categories' => $expense] as $table => $id) {
            $this->assertDatabaseHas($table, ['id' => $id, 'business_id' => $business]);
        }
        $this->assertDatabaseHas('products', ['id' => $product, 'base_price' => 3.5, 'sku' => 'COFFEE']);
        $this->assertDatabaseHas('customers', ['id' => $customer, 'phone' => 'fixture']);
        $this->assertTrue(app(TenantIntegrity::class)->report()['ready']);
    }

    public function test_multi_business_backfill_quarantines_ambiguous_and_unattributed_records(): void
    {
        $this->legacySchema();
        $a = Business::factory()->create();
        $b = Business::factory()->create();
        $branchA = Branch::factory()->create(['business_id' => $a->id]);
        $branchB = Branch::factory()->create(['business_id' => $b->id]);
        $private = DB::table('categories')->insertGetId(['name' => 'Private', 'branch_id' => $branchA->id]);
        $global = DB::table('categories')->insertGetId(['name' => 'Old shared', 'branch_id' => null]);
        $product = DB::table('products')->insertGetId(['category_id' => $global, 'name' => 'Old shared', 'base_price' => 3.5]);
        foreach ([$branchA, $branchB] as $branch) DB::table('branch_product')->insert(['branch_id' => $branch->id, 'product_id' => $product, 'is_available' => true]);
        $customer = DB::table('customers')->insertGetId(['name' => 'Unknown owner', 'branch_id' => null]);
        $this->migrateOwnership();
        $this->assertDatabaseHas('categories', ['id' => $private, 'business_id' => $a->id]);
        $this->assertDatabaseHas('products', ['id' => $product, 'business_id' => null, 'base_price' => 3.5]);
        $this->assertDatabaseHas('categories', ['id' => $global, 'business_id' => null]);
        $this->assertDatabaseHas('customers', ['id' => $customer, 'business_id' => null]);
        $this->assertDatabaseCount('branch_product', 2);
        $this->assertFalse(app(TenantIntegrity::class)->report()['ready']);
        $this->artisan('pos:tenancy-check', ['--json' => true])->assertExitCode(1);
    }
}
