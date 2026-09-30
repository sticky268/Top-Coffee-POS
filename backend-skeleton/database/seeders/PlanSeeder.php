<?php

namespace Database\Seeders;

use App\Models\Plan;
use Illuminate\Database\Seeder;

class PlanSeeder extends Seeder
{
    /**
     * Seed the SaaS subscription plans.
     */
    public function run(): void
    {
        $plans = [
            [
                'name' => '1 Branch',
                'slug' => '1-branch',
                'branch_limit' => 1,
            ],
            [
                'name' => '2 Branches',
                'slug' => '2-branches',
                'branch_limit' => 2,
            ],
            [
                'name' => '3 Branches',
                'slug' => '3-branches',
                'branch_limit' => 3,
            ],
            [
                'name' => '4 Branches',
                'slug' => '4-branches',
                'branch_limit' => 4,
            ],
            [
                'name' => '5 Branches',
                'slug' => '5-branches',
                'branch_limit' => 5,
            ],
            [
                'name' => '10 Branches',
                'slug' => '10-branches',
                'branch_limit' => 10,
            ],
        ];

        foreach ($plans as $plan) {
            Plan::updateOrCreate(
                ['slug' => $plan['slug']],
                [
                    'name' => $plan['name'],
                    'branch_limit' => $plan['branch_limit'],
                    'price' => 0,
                    'billing_interval' => 'monthly',
                    'is_active' => true,
                ]
            );
        }
    }
}