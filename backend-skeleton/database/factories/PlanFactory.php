<?php

namespace Database\Factories;

use App\Models\Plan;
use Illuminate\Database\Eloquent\Factories\Factory;
use Illuminate\Support\Str;

/**
 * @extends Factory<Plan>
 */
class PlanFactory extends Factory
{
    /**
     * Define the model's default state.
     *
     * @return array<string, mixed>
     */
    public function definition(): array
    {
        $name = fake()->randomElement([
            'Starter',
            'Business',
            'Enterprise',
        ]);

        return [
            'name' => $name,
            'slug' => Str::slug($name) . '-' . fake()->unique()->numberBetween(1000, 9999),
            'branch_limit' => fake()->numberBetween(1, 10),
            'price' => fake()->randomFloat(2, 0, 1000),
            'billing_interval' => 'monthly',
            'is_active' => true,
        ];
    }
}
