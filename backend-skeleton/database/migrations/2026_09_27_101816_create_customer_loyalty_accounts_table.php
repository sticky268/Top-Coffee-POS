<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('customer_loyalty_accounts', function (Blueprint $table) {
            $table->id();
            $table->foreignId('customer_id')
                ->constrained()
                ->cascadeOnDelete();
            $table->unsignedBigInteger('points_balance')->default(0);
            $table->unsignedBigInteger('lifetime_earned')->default(0);
            $table->unsignedBigInteger('lifetime_redeemed')->default(0);
            $table->timestamps();

            $table->unique('customer_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('customer_loyalty_accounts');
    }
};