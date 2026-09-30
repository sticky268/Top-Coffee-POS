<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        Schema::table('businesses', function (Blueprint $table) {
            $table->foreignId('plan_id')
                ->nullable()
                ->after('id')
                ->constrained('plans')
                ->restrictOnDelete();

            $table->string('status')
                ->default('trial')
                ->after('is_active');

            $table->timestamp('started_at')
                ->nullable()
                ->after('status');

            $table->timestamp('expires_at')
                ->nullable()
                ->after('started_at');

            $table->index('status');
            $table->index('expires_at');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('businesses', function (Blueprint $table) {
            $table->dropForeign(['plan_id']);
            $table->dropIndex(['status']);
            $table->dropIndex(['expires_at']);
            $table->dropColumn([
                'plan_id',
                'status',
                'started_at',
                'expires_at',
            ]);
        });
    }
};
