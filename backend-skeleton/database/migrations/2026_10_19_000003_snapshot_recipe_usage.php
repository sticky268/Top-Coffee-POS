<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\DB;

return new class extends Migration {
    public function up(): void
    {
        Schema::table('order_items', fn (Blueprint $t) => $t->json('recipe_usage_snapshot')->nullable());
        Schema::table('stock_movements', fn (Blueprint $t) => $t->index(['branch_id', 'created_at', 'id'], 'stock_branch_time_id'));
    }
    public function down(): void
    {
        // InnoDB can replace an automatically created FK index with this composite.
        // Restore a single-column supporting index before dropping the composite.
        if (DB::getDriverName() === 'mysql' && ! Schema::hasIndex('stock_movements', ['branch_id'])) {
            Schema::table('stock_movements', fn (Blueprint $t) => $t->index('branch_id', 'stock_branch_fk_support'));
        }
        Schema::table('stock_movements', fn (Blueprint $t) => $t->dropIndex('stock_branch_time_id'));
        Schema::table('order_items', fn (Blueprint $t) => $t->dropColumn('recipe_usage_snapshot'));
    }
};
