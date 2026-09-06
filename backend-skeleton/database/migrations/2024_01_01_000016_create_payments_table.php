<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('payments', function (Blueprint $table) {
            $table->id();
            $table->foreignId('order_id')->constrained()->restrictOnDelete();
            $table->enum('method', ['cash', 'card', 'qr', 'split']);
            $table->decimal('amount', 12, 2);
            $table->decimal('tendered', 12, 2)->nullable();   // cash given
            $table->decimal('change_due', 12, 2)->nullable();
            $table->enum('status', ['pending', 'completed', 'failed', 'refunded', 'partially_refunded'])->default('pending');
            $table->string('reference')->nullable(); // provider transaction id, never store card numbers
            $table->foreignId('processed_by')->constrained('users')->restrictOnDelete();
            $table->timestamps();

            $table->index(['order_id', 'status']);
        });

        Schema::create('payment_refunds', function (Blueprint $table) {
            $table->id();
            $table->foreignId('payment_id')->constrained()->restrictOnDelete();
            $table->decimal('amount', 12, 2);
            $table->string('reason');
            $table->foreignId('processed_by')->constrained('users')->restrictOnDelete();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('payment_refunds');
        Schema::dropIfExists('payments');
    }
};
