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
        Schema::table('restaurant_tables', function (Blueprint $table) {
            $table->string('section')->nullable()->after('status');
            $table->string('shape')->default('square')->after('section');
            $table->string('color')->nullable()->after('shape');
            $table->boolean('is_active')->default(true)->after('color');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('restaurant_tables', function (Blueprint $table) {
            $table->dropColumn([
                'section',
                'shape',
                'color',
                'is_active',
            ]);
        });
    }
};
