<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;

class DatabaseSeeder extends Seeder
{
    public function run(): void
    {
        $this->call([
            PlanSeeder::class,
            RolePermissionSeeder::class,
            BranchSeeder::class,
            UserSeeder::class,
            UnitSeeder::class,
            CategoryProductSeeder::class,
            ExpenseCategorySeeder::class,
        ]);
    }
}
