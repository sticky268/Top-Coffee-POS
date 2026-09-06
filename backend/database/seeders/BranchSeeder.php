<?php

namespace Database\Seeders;

use App\Models\Branch;
use Illuminate\Database\Seeder;

class BranchSeeder extends Seeder
{
    public function run(): void
    {
        Branch::firstOrCreate(
            ['code' => 'PP-01'],
            ['name' => 'Top Coffee - Riverside', 'address' => 'Phnom Penh', 'timezone' => 'Asia/Phnom_Penh']
        );

        Branch::firstOrCreate(
            ['code' => 'PP-02'],
            ['name' => 'Top Coffee - BKK1', 'address' => 'Phnom Penh', 'timezone' => 'Asia/Phnom_Penh']
        );
    }
}
