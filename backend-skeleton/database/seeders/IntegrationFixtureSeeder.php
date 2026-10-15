<?php

namespace Database\Seeders;

use App\Models\{Business, Branch, User, Category, Product, RestaurantTable};
use Illuminate\Database\Seeder;

// Disposable CI fixtures only. Never invoked by DatabaseSeeder.
class IntegrationFixtureSeeder extends Seeder
{
    public function run(): void
    {
        if (! app()->environment('testing') || User::count() !== 0 || Branch::count() !== 0 || Product::count() !== 0) {
            throw new \RuntimeException('Integration fixtures require an unused testing database.');
        }
        $this->call(RolePermissionSeeder::class);
        $business = Business::factory()->create(['name' => 'CI Cafe']);
        $branch = Branch::create(['business_id' => $business->id, 'name' => 'CI Branch', 'code' => 'CI-01', 'timezone' => 'UTC', 'is_active' => true]);
        $user = User::factory()->create(['business_id' => $business->id, 'email' => 'cashier@ci.invalid', 'password' => 'ci-disposable-password']);
        $user->assignRole('cashier');
        $user->branches()->attach($branch->id, ['is_primary' => true]);
        $category = Category::forceCreate(['business_id' => $business->id, 'name' => 'Coffee', 'sort_order' => 1]);
        $product = Product::forceCreate(['business_id' => $business->id, 'category_id' => $category->id, 'name' => 'CI Latte', 'base_price' => 3.5, 'is_active' => true]);
        $product->branches()->attach($branch->id, ['is_available' => true]);
        RestaurantTable::create(['branch_id' => $branch->id, 'name' => 'CI Table', 'capacity' => 2, 'is_active' => true, 'status' => 'available']);

        // A separate disposable tenant keeps manager step-up requirements from
        // changing the daily cashier smoke fixture. PINs are enrolled through
        // the real Settings UI, never seeded or bypassed.
        $managed = Business::factory()->create(['name' => 'CI Manager Cafe',
            'require_cash_shift' => true, 'require_manager_controls' => true, 'manager_discount_percent' => 0]);
        $managedBranch = Branch::create(['business_id' => $managed->id, 'name' => 'CI Manager Branch',
            'code' => 'CI-PIN', 'timezone' => 'UTC', 'is_active' => true]);
        foreach (['manager@ci.invalid', 'locked-manager@ci.invalid'] as $email) {
            $manager = User::factory()->create(['business_id' => $managed->id, 'name' => 'CI Manager',
                'email' => $email, 'password' => 'ci-disposable-password']);
            $manager->assignRole('manager');
            $manager->branches()->attach($managedBranch->id, ['is_primary' => true]);
        }
        $managedCategory = Category::forceCreate(['business_id' => $managed->id, 'name' => 'Approval Coffee', 'sort_order' => 1]);
        $managedProduct = Product::forceCreate(['business_id' => $managed->id, 'category_id' => $managedCategory->id,
            'name' => 'CI Approval Latte', 'base_price' => 3.5, 'is_active' => true]);
        $managedProduct->branches()->attach($managedBranch->id, ['is_available' => true]);
        RestaurantTable::create(['branch_id' => $managedBranch->id, 'name' => 'CI Approval Table',
            'capacity' => 2, 'is_active' => true, 'status' => 'available']);
    }
}
