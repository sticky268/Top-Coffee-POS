<?php

namespace Database\Seeders;

use App\Models\ExpenseCategory;
use Illuminate\Database\Seeder;

class ExpenseCategorySeeder extends Seeder
{
    public function run(): void
    {
        $categories = [
            'Rent',
            'Utilities',
            'Supplies',
            'Salaries',
            'Maintenance',
            'Marketing',
            'Other',
        ];

        $business = \App\Models\Business::where('slug', 'top-coffee-demo')->firstOrFail();
        foreach ($categories as $name) {
            ExpenseCategory::unguarded(fn () => ExpenseCategory::firstOrCreate([
                'business_id' => $business->id,
                'name' => $name,
            ]));
        }
    }
}
