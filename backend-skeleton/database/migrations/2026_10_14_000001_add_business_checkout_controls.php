<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        Schema::table('businesses', function (Blueprint $table) {
            // Existing installations activate after reconciling pending cash.
            $table->boolean('require_cash_shift')->default(false);
            $table->boolean('require_manager_controls')->default(false);
            $table->decimal('manager_discount_percent', 5, 2)->default(10);
        });
    }
    public function down(): void
    {
        Schema::table('businesses', fn (Blueprint $table) => $table->dropColumn(['require_cash_shift', 'require_manager_controls', 'manager_discount_percent']));
    }
};
