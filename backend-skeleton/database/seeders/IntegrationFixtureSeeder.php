<?php

namespace Database\Seeders;

use App\Models\{Business, Branch, User, Category, Product, RestaurantTable};
use Illuminate\Database\Seeder;

// Disposable CI fixtures only. Never invoked by DatabaseSeeder.
class IntegrationFixtureSeeder extends Seeder
{
    public function run(): void
    {
        if (! app()->environment('testing') || Business::count() !== 0) {
            throw new \RuntimeException('Integration fixtures require an empty testing database.');
        }
        $this->call(RolePermissionSeeder::class);
        $business = Business::factory()->create(['name' => 'CI Cafe']);
        $branch = Branch::create(['business_id' => $business->id, 'name' => 'CI Branch', 'code' => 'CI-01', 'timezone' => 'UTC', 'is_active' => true]);
        $user = User::factory()->create(['business_id' => $business->id, 'email' => 'cashier@ci.invalid', 'password' => 'ci-disposable-password']);
        $user->assignRole('cashier');
        $user->branches()->attach($branch->id, ['is_primary' => true]);
        $category = Category::create(['business_id' => $business->id, 'name' => 'Coffee', 'sort_order' => 1]);
        $product = Product::create(['business_id' => $business->id, 'category_id' => $category->id, 'name' => 'CI Latte', 'base_price' => 3.5, 'is_active' => true]);
        $product->branches()->attach($branch->id, ['is_available' => true]);
        RestaurantTable::create(['branch_id' => $branch->id, 'name' => 'CI Table', 'capacity' => 2, 'is_active' => true, 'status' => 'available']);
    }
}
