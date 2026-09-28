<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('loyalty_settings', function (Blueprint $table) {
            $table->id();
            $table->foreignId('branch_id')
                ->nullable()
                ->constrained()
                ->cascadeOnDelete();
            $table->boolean('is_enabled')->default(false);
            $table->decimal('points_per_currency_unit', 10, 4)->default(1);
            $table->decimal('points_per_reward_currency_unit', 10, 4)->default(100);
            $table->unsignedInteger('minimum_redeem_points')->default(100);
            $table->boolean('redemption_enabled')->default(true);
            $table->unsignedInteger('expiration_months')->nullable();
            $table->timestamps();

            $table->unique('branch_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('loyalty_settings');
    }
};