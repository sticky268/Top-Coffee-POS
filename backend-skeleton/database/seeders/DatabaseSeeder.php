<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;

class DatabaseSeeder extends Seeder
{
    public function run(): void
    {
        if (config('app.env') === 'production') {
            throw new \LogicException('Demo seeding is disabled in production. Use pos:onboard-business for real business setup.');
        }
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
