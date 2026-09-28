<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('loyalty_transactions', function (Blueprint $table) {
            $table->id();
            $table->foreignId('customer_loyalty_account_id')
                ->constrained()
                ->restrictOnDelete();
            $table->foreignId('customer_id')
                ->constrained()
                ->restrictOnDelete();
            $table->foreignId('branch_id')
                ->nullable()
                ->constrained()
                ->nullOnDelete();
            $table->foreignId('order_id')
                ->nullable()
                ->constrained()
                ->nullOnDelete();
            $table->enum('type', [
                'earned',
                'redeemed',
                'expired',
                'adjustment',
            ]);
            $table->bigInteger('points');
            $table->unsignedBigInteger('balance_after')->default(0);
            $table->string('description')->nullable();
            $table->timestamps();

            $table->index(['customer_id', 'created_at']);
            $table->index(['branch_id', 'created_at']);
            $table->index(['order_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('loyalty_transactions');
    }
};