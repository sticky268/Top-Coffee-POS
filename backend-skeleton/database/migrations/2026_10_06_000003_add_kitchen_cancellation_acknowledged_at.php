<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('kitchen_tickets', function (Blueprint $table) {
            $table->timestamp('cancellation_acknowledged_at')->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('kitchen_tickets', function (Blueprint $table) {
            $table->dropColumn('cancellation_acknowledged_at');
        });
    }
};
