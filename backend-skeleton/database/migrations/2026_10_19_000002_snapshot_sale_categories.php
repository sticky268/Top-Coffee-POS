<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('order_items', function (Blueprint $t) {
            // No backfill: today's category cannot establish a historical fact.
            $t->unsignedBigInteger('sale_category_id')->nullable();
            $t->string('sale_category_name')->nullable();
            $t->boolean('sale_category_captured')->default(false);
        });
    }

    public function down(): void
    {
        Schema::table('order_items', fn (Blueprint $t) => $t->dropColumn(['sale_category_id', 'sale_category_name', 'sale_category_captured']));
    }
};
