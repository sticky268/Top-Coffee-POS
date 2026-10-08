<?php

namespace Database\Seeders;

use App\Models\Branch;
use App\Models\Category;
use App\Models\Product;
use Illuminate\Database\Seeder;

class CategoryProductSeeder extends Seeder
{
    public function run(): void
    {
        // Demo data belongs only to the demo business, never every tenant.
        $business = \App\Models\Business::where('slug', 'top-coffee-demo')->firstOrFail();
        \Illuminate\Database\Eloquent\Model::unguarded(function () use ($business) {
        $branches = Branch::where('business_id', $business->id)->get();

        $coffee = Category::firstOrCreate(['business_id' => $business->id, 'name' => 'Coffee', 'branch_id' => null], ['sort_order' => 1]);
        $tea = Category::firstOrCreate(['business_id' => $business->id, 'name' => 'Tea', 'branch_id' => null], ['sort_order' => 2]);

        $latte = Product::firstOrCreate(
            ['business_id' => $business->id, 'sku' => 'COF-LATTE'],
            ['category_id' => $coffee->id, 'name' => 'Iced Latte', 'base_price' => 3.50]
        );

        $americano = Product::firstOrCreate(
            ['business_id' => $business->id, 'sku' => 'COF-AMER'],
            ['category_id' => $coffee->id, 'name' => 'Americano', 'base_price' => 2.75]
        );

        $greenTea = Product::firstOrCreate(
            ['business_id' => $business->id, 'sku' => 'TEA-GREEN'],
            ['category_id' => $tea->id, 'name' => 'Green Tea', 'base_price' => 2.50]
        );

        foreach ([$latte, $americano, $greenTea] as $product) {
            foreach ($branches as $branch) {
                $branch->products()->syncWithoutDetaching([$product->id => ['is_available' => true]]);
            }
        }
        });
    }
}
