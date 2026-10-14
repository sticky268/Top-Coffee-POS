<?php

namespace Tests\Feature;

use App\Models\{Business, Branch, User, Category, Product, ProductVariant, Unit, Ingredient, Customer};
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;
use Tests\TestCase;

class OperationsMigrationRehearsalTest extends TestCase
{
    private bool $disposable = false;

    protected function setUp(): void
    {
        parent::setUp();
        if (getenv('RUN_OPERATIONS_RELEASE_CHECKS') !== '1') $this->markTestSkipped('Opt-in disposable MySQL migration rehearsal.');
        $this->assertTrue(app()->environment('testing'));
        $this->assertSame('mysql', config('database.default'));
        $this->assertSame('operations_testing', config('database.connections.mysql.database'));
        $this->disposable = true;
        // This candidate adds checkout controls after the daily-operations migration.
        // Rehearse from the same pre-operations schema by rolling back both.
        $this->artisan('migrate:fresh', ['--force' => true])->assertExitCode(0);
        $this->artisan('migrate:rollback', ['--step' => 2, '--force' => true])->assertExitCode(0);
        $this->assertFalse(Schema::hasTable('cashier_shifts'));
        $this->assertFalse(Schema::hasColumn('ingredients', 'average_unit_cost'));
    }

    protected function tearDown(): void
    {
        if ($this->disposable) $this->artisan('migrate:fresh', ['--force' => true]);
        parent::tearDown();
    }

    public function test_populated_previous_schema_survives_upgrade_rollback_and_reapplication(): void
    {
        $business = Business::factory()->create();
        $branch = Branch::create(['business_id' => $business->id, 'name' => 'Historical cafe', 'code' => 'HIST']);
        $actor = User::factory()->create(['business_id' => $business->id]);
        $category = Category::forceCreate(['business_id' => $business->id, 'name' => 'Coffee']);
        $product = Product::forceCreate(['business_id' => $business->id, 'category_id' => $category->id, 'name' => 'កាហ្វេ Latte', 'base_price' => 3.5, 'is_active' => true]);
        $variant = ProductVariant::create(['product_id' => $product->id, 'name' => 'Large', 'price_delta' => 1, 'is_active' => true]);
        $unit = Unit::create(['name' => 'Kilogram', 'abbreviation' => 'kg', 'conversion_factor' => 1000]);
        $ingredient = Ingredient::create(['branch_id' => $branch->id, 'unit_id' => $unit->id, 'name' => 'Beans', 'is_active' => true]);
        $customer = Customer::forceCreate(['business_id' => $business->id, 'branch_id' => $branch->id, 'name' => 'Historical regular']);
        $stamp = ['created_at' => '2026-09-01 02:30:00', 'updated_at' => '2026-09-01 02:30:00'];
        $order = DB::table('orders')->insertGetId($stamp + ['uuid' => (string) Str::uuid(), 'branch_id' => $branch->id, 'user_id' => $actor->id, 'customer_id' => $customer->id, 'order_number' => 42, 'order_type' => 'takeaway', 'status' => 'completed', 'subtotal' => 10, 'discount_total' => 1, 'total' => 9, 'completed_at' => $stamp['created_at']]);
        DB::table('order_items')->insert($stamp + ['order_id' => $order, 'product_id' => $product->id, 'product_variant_id' => $variant->id, 'quantity' => 2, 'unit_price' => 5, 'notes' => 'ស្ករតិច']);
        $payment = DB::table('payments')->insertGetId($stamp + ['order_id' => $order, 'method' => 'cash', 'amount' => 9, 'tendered' => 10, 'change_due' => 1, 'status' => 'partially_refunded', 'processed_by' => $actor->id]);
        DB::table('payment_refunds')->insert($stamp + ['payment_id' => $payment, 'amount' => 2, 'reason' => 'Historical correction', 'processed_by' => $actor->id]);
        DB::table('stock_movements')->insert($stamp + ['ingredient_id' => $ingredient->id, 'branch_id' => $branch->id, 'type' => 'purchase', 'quantity' => 3, 'balance_after' => 3, 'created_by' => $actor->id]);
        DB::table('stock_movements')->insert($stamp + ['ingredient_id' => $ingredient->id, 'branch_id' => $branch->id, 'type' => 'sale_deduction', 'quantity' => -0.655, 'balance_after' => 2.345, 'created_by' => $actor->id, 'reference_type' => 'App\\Models\\Order', 'reference_id' => $order]);
        DB::table('ingredients')->where('id', $ingredient->id)->update(['current_stock' => 2.345]);
        $account = DB::table('customer_loyalty_accounts')->insertGetId($stamp + ['customer_id' => $customer->id, 'points_balance' => 7, 'lifetime_earned' => 9, 'lifetime_redeemed' => 2]);
        DB::table('loyalty_transactions')->insert($stamp + ['customer_loyalty_account_id' => $account, 'customer_id' => $customer->id, 'branch_id' => $branch->id, 'order_id' => $order, 'type' => 'earned', 'points' => 9, 'balance_after' => 9]);
        $snapshot = [];
        foreach (['businesses', 'branches', 'users', 'customers', 'products', 'product_variants', 'orders', 'order_items', 'payments', 'payment_refunds', 'ingredients', 'stock_movements', 'customer_loyalty_accounts', 'loyalty_transactions'] as $table) {
            $columns = Schema::getColumnListing($table);
            $snapshot[$table] = ['columns' => $columns, 'rows' => DB::table($table)->select($columns)->orderBy('id')->get()->toJson()];
        }
        $verify = function () use ($snapshot) {
            foreach ($snapshot as $table => $before) {
                $this->assertSame($before['rows'], DB::table($table)->select($before['columns'])->orderBy('id')->get()->toJson(), "$table historical values must remain identical");
            }
        };
        $this->artisan('migrate', ['--force' => true])->assertExitCode(0);
        $verify();
        $this->assertNull(DB::table('ingredients')->value('average_unit_cost'));
        $this->assertNull(DB::table('stock_movements')->value('unit_cost'));
        $this->assertNull(DB::table('order_items')->value('ingredient_cost'));
        $this->assertNull(DB::table('payments')->value('shift_id'));
        $this->assertSame('cashier_recorded', DB::table('payments')->value('verification'));
        $this->assertSame('consumed', DB::table('payment_refunds')->value('inventory_disposition'));
        $this->assertEquals(1, DB::table('product_variants')->value('recipe_multiplier'));
        $this->assertEquals(0, DB::table('customer_loyalty_accounts')->value('refund_points_debt'));
        $this->assertEquals(0, DB::table('orders')->value('supplemental_total'));
        $this->artisan('migrate', ['--force' => true])->assertExitCode(0);
        $verify();
        // Rollback rehearsal occurs before any new shift/correction data is written.
        $this->artisan('migrate:rollback', ['--step' => 2, '--force' => true])->assertExitCode(0);
        $verify();
        $this->artisan('migrate', ['--force' => true])->assertExitCode(0);
        $verify();

        // Verify the local rehearsal command against a populated restored copy.
        $this->artisan('migrate:rollback', ['--step' => 2, '--force' => true])->assertExitCode(0);
        $target = 'top_coffee_pos_pr7_rehearsal_20000101';
        DB::statement('CREATE DATABASE `'.$target.'` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci');
        try {
            $copyConfig = DB::connection()->getConfig();
            $copyConfig['database'] = $target;
            $copyConfig['url'] = null;
            $copyConfig['name'] = 'rehearsal_setup';
            config(['database.connections.rehearsal_setup' => $copyConfig]);
            $copy = DB::connection('rehearsal_setup');
            $copy->statement('SET FOREIGN_KEY_CHECKS=0');
            foreach (DB::select("SHOW FULL TABLES WHERE Table_type = 'BASE TABLE'") as $entry) {
                $table = array_values((array) $entry)[0];
                $quoted = '`'.str_replace('`', '``', $table).'`';
                $create = array_values((array) DB::selectOne('SHOW CREATE TABLE '.$quoted))[1];
                $copy->statement($create);
                foreach (DB::table($table)->get() as $row) $copy->table($table)->insert((array) $row);
            }
            $copy->statement('SET FOREIGN_KEY_CHECKS=1');
            $migrationRows = DB::table('migrations')->orderBy('id')->get()->toJson();
            $this->artisan('pos:rehearse-migration', ['--database' => $target])
                ->expectsOutputToContain('PASS: all original record values are unchanged.')
                ->assertExitCode(0);
            $this->assertSame('mysql', DB::getDefaultConnection());
            $this->assertFalse(Schema::connection('mysql')->hasTable('cashier_shifts'));
            $this->assertFalse(Schema::connection('mysql')->hasColumn('ingredients', 'average_unit_cost'));
            $this->assertSame($migrationRows, DB::table('migrations')->orderBy('id')->get()->toJson());
            $this->assertTrue(Schema::connection('rehearsal_setup')->hasTable('cashier_shifts'));
            $verify();
        } finally {
            DB::purge('rehearsal_setup');
            DB::statement('DROP DATABASE `'.$target.'`');
        }
    }
}
