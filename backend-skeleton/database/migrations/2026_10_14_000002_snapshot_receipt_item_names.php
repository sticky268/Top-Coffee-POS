<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // Nullable legacy fields: never invent historical names or rewrite sales.
        Schema::table('order_items', function (Blueprint $table) {
            $table->string('product_name')->nullable();
            $table->string('variant_name')->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('order_items', function (Blueprint $table) {
            $table->dropColumn(['product_name', 'variant_name']);
        });
    }
};
