<?php

namespace Database\Factories;

use App\Models\Business;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends \Illuminate\Database\Eloquent\Factories\Factory<\App\Models\Branch>
 */
class BranchFactory extends Factory
{
    public function definition(): array
    {
        return [
            'business_id' => Business::factory(),
            'name' => fake()->company(),
            'code' => fake()->unique()->bothify('BR-##'),
            'address' => fake()->address(),
            'phone' => fake()->phoneNumber(),
            'timezone' => 'Asia/Phnom_Penh',
            'is_active' => true,
        ];
    }
}