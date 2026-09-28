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

        foreach ($categories as $name) {
            ExpenseCategory::firstOrCreate([
                'name' => $name,
            ]);
        }
    }
}
