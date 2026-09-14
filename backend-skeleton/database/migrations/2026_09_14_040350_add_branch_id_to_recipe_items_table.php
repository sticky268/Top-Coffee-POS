<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('recipe_items', function (Blueprint $table) {
            $table->foreignId('branch_id')
                ->after('id')
                ->constrained()
                ->cascadeOnDelete();

            $table->index(['branch_id', 'product_id']);
        });
    }

    public function down(): void
    {
        Schema::table('recipe_items', function (Blueprint $table) {
            $table->dropForeign(['branch_id']);
            $table->dropIndex(['branch_id', 'product_id']);
            $table->dropColumn('branch_id');
        });
    }
};