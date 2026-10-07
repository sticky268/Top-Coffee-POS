<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('branches', function (Blueprint $table) {
            $table->boolean('use_kitchen_display')->default(true)->after('is_active');
        });

        Schema::table('kitchen_tickets', function (Blueprint $table) {
            $table->string('cancellation_reason')->nullable()->after('cancellation_acknowledged_at');
            $table->foreignId('cancelled_by')->nullable()->after('cancellation_reason')
                ->constrained('users')->nullOnDelete();
        });
    }

    public function down(): void
    {
        Schema::table('kitchen_tickets', function (Blueprint $table) {
            $table->dropConstrainedForeignId('cancelled_by');
            $table->dropColumn('cancellation_reason');
        });

        Schema::table('branches', function (Blueprint $table) {
            $table->dropColumn('use_kitchen_display');
        });
    }
};
