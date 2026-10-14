<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        Schema::create('cashier_shifts', function (Blueprint $t) {
            $t->id();
            $t->foreignId('branch_id')->constrained()->restrictOnDelete();
            $t->foreignId('user_id')->constrained()->restrictOnDelete();
            $t->string('status')->default('open');
            $t->decimal('opening_cash', 12, 2);
            $t->decimal('expected_cash', 12, 2)->nullable();
            $t->decimal('counted_cash', 12, 2)->nullable();
            $t->decimal('difference', 12, 2)->nullable();
            $t->text('closing_reason')->nullable();
            $t->timestamp('closed_at')->nullable();
            $t->foreignId('reviewed_by')->nullable()->constrained('users')->restrictOnDelete();
            $t->timestamp('reviewed_at')->nullable();
            $t->timestamps();
            $t->index(['branch_id', 'user_id', 'status']);
        });
        Schema::create('operation_requests', function (Blueprint $t) {
            $t->id();
            $t->foreignId('branch_id')->constrained()->restrictOnDelete();
            $t->foreignId('user_id')->constrained()->restrictOnDelete();
            $t->uuid('uuid');
            $t->string('operation');
            $t->string('fingerprint', 64);
            $t->json('result')->nullable();
            $t->timestamps();
            $t->unique(['user_id', 'uuid']);
        });
        Schema::create('cash_movements', function (Blueprint $t) {
            $t->id();
            $t->foreignId('shift_id')->constrained('cashier_shifts')->restrictOnDelete();
            $t->string('type');
            $t->decimal('amount', 12, 2);
            $t->string('reason');
            $t->timestamps();
        });
        Schema::table('payments', function (Blueprint $t) {
            $t->foreignId('shift_id')->nullable()->constrained('cashier_shifts')->restrictOnDelete();
            $t->string('verification')->default('cashier_recorded');
        });
        Schema::table('payment_refunds', function (Blueprint $t) {
            $t->foreignId('shift_id')->nullable()->constrained('cashier_shifts')->restrictOnDelete();
            $t->string('inventory_disposition')->default('consumed');
        });
        Schema::table('customer_loyalty_accounts', fn (Blueprint $t) => $t->unsignedBigInteger('refund_points_debt')->default(0));
        Schema::table('ingredients', fn (Blueprint $t) => $t->decimal('average_unit_cost', 14, 6)->nullable());
        Schema::table('stock_movements', fn (Blueprint $t) => $t->decimal('unit_cost', 14, 6)->nullable());
        Schema::table('order_items', fn (Blueprint $t) => $t->decimal('ingredient_cost', 14, 6)->nullable());
        Schema::table('orders', function (Blueprint $t) {
            $t->decimal('supplemental_total', 12, 2)->default(0);
            $t->timestamp('inventory_disposed_at')->nullable();
            $t->unsignedBigInteger('refunded_loyalty_points')->default(0);
        });
        Schema::table('product_variants', fn (Blueprint $t) => $t->decimal('recipe_multiplier', 10, 3)->default(1));
    }

    public function down(): void
    {
        Schema::table('product_variants', fn (Blueprint $t) => $t->dropColumn('recipe_multiplier'));
        Schema::table('orders', fn (Blueprint $t) => $t->dropColumn(['supplemental_total', 'inventory_disposed_at', 'refunded_loyalty_points']));
        Schema::table('order_items', fn (Blueprint $t) => $t->dropColumn('ingredient_cost'));
        Schema::table('stock_movements', fn (Blueprint $t) => $t->dropColumn('unit_cost'));
        Schema::table('ingredients', fn (Blueprint $t) => $t->dropColumn('average_unit_cost'));
        Schema::table('customer_loyalty_accounts', fn (Blueprint $t) => $t->dropColumn('refund_points_debt'));
        Schema::table('payment_refunds', function (Blueprint $t) {
            $t->dropConstrainedForeignId('shift_id');
            $t->dropColumn('inventory_disposition');
        });
        Schema::table('payments', function (Blueprint $t) {
            $t->dropConstrainedForeignId('shift_id');
            $t->dropColumn('verification');
        });
        Schema::dropIfExists('cash_movements');
        Schema::dropIfExists('operation_requests');
        Schema::dropIfExists('cashier_shifts');
    }
};
