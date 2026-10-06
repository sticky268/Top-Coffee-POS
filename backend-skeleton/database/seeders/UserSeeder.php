<?php

namespace Database\Seeders;

use App\Models\Branch;
use App\Models\Business;
use App\Models\User;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\Hash;

class UserSeeder extends Seeder
{
    public function run(): void
    {
        $business = Business::where('slug', 'top-coffee-demo')->firstOrFail();

        $branch1 = Branch::where('code', 'PP-01')->first();
        $branch2 = Branch::where('code', 'PP-02')->first();

        $admin = User::firstOrCreate(
            ['email' => 'admin@topcoffee.test'],
            ['business_id' => $business->id, 'name' => 'Admin User', 'password' => Hash::make('password')]
        );
        $admin->assignRole('admin');
        $admin->branches()->syncWithoutDetaching([$branch1->id => ['is_primary' => true], $branch2->id => []]);

        $manager = User::firstOrCreate(
            ['email' => 'manager@topcoffee.test'],
            ['business_id' => $business->id, 'name' => 'Manager User', 'password' => Hash::make('password')]
        );
        $manager->assignRole('manager');
        $manager->branches()->syncWithoutDetaching([$branch1->id => ['is_primary' => true]]);

        $cashier = User::firstOrCreate(
            ['email' => 'cashier@topcoffee.test'],
            ['business_id' => $business->id, 'name' => 'Cashier User', 'password' => Hash::make('password')]
        );
        $cashier->assignRole('cashier');
        $cashier->branches()->syncWithoutDetaching([$branch1->id => ['is_primary' => true]]);

        $kitchen = User::firstOrCreate(
            ['email' => 'kitchen@topcoffee.test'],
            ['business_id' => $business->id, 'name' => 'Kitchen Staff', 'password' => Hash::make('password')]
        );
        $kitchen->assignRole('kitchen_staff');
        $kitchen->branches()->syncWithoutDetaching([$branch1->id => ['is_primary' => true]]);
    }
}
