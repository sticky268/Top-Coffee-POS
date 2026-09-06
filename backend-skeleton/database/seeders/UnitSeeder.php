<?php

namespace Database\Seeders;

use App\Models\Unit;
use Illuminate\Database\Seeder;

class UnitSeeder extends Seeder
{
    public function run(): void
    {
        Unit::firstOrCreate(['abbreviation' => 'g'], ['name' => 'Gram', 'conversion_factor' => 1]);
        Unit::firstOrCreate(['abbreviation' => 'kg'], ['name' => 'Kilogram', 'conversion_factor' => 1000]);
        Unit::firstOrCreate(['abbreviation' => 'ml'], ['name' => 'Milliliter', 'conversion_factor' => 1]);
        Unit::firstOrCreate(['abbreviation' => 'l'], ['name' => 'Liter', 'conversion_factor' => 1000]);
        Unit::firstOrCreate(['abbreviation' => 'pc'], ['name' => 'Piece', 'conversion_factor' => 1]);
    }
}
