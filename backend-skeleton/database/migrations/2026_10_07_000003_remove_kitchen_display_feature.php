<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // These guards make the cleanup safe both for existing development
        // databases that already ran the KDS migrations and for fresh installs
        // where those removed migrations never existed.
        Schema::dropIfExists('kitchen_item_voids');
        Schema::dropIfExists('kitchen_ticket_items');
        Schema::dropIfExists('kitchen_tickets');

        if (Schema::hasColumn('branches', 'use_kitchen_display')) {
            Schema::table('branches', function (Blueprint $table) {
                $table->dropColumn('use_kitchen_display');
            });
        }
    }

    public function down(): void
    {
        // Kitchen Display has been intentionally removed from the product.
    }
};
