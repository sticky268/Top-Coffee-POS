<?php

namespace Database\Seeders;

use App\Models\Branch;
use App\Models\Business;
use App\Models\Plan;
use Illuminate\Database\Seeder;

class BranchSeeder extends Seeder
{
    public function run(): void
    {
        $plan = Plan::where('slug', '2-branches')->firstOrFail();

        $business = Business::firstOrCreate(
            ['slug' => 'top-coffee-demo'],
            [
                'name' => 'Top Coffee Demo',
                'plan_id' => $plan->id,
                'status' => 'active',
                'is_active' => true,
            ]
        );

        Branch::firstOrCreate(
            ['code' => 'PP-01'],
            ['business_id' => $business->id, 'name' => 'Top Coffee - Riverside', 'address' => 'Phnom Penh', 'timezone' => 'Asia/Phnom_Penh']
        );

        Branch::firstOrCreate(
            ['code' => 'PP-02'],
            ['business_id' => $business->id, 'name' => 'Top Coffee - BKK1', 'address' => 'Phnom Penh', 'timezone' => 'Asia/Phnom_Penh']
        );
    }
}
