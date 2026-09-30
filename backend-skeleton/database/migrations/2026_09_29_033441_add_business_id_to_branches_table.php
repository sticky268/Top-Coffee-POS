<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        Schema::table('branches', function (Blueprint $table) {
            $table->unsignedBigInteger('business_id')->nullable()->after('id');
        });

        $businessId = DB::table('businesses')->insertGetId([
            'name' => 'Top Coffee',
            'slug' => 'top-coffee',
            'is_active' => true,
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        DB::table('branches')->update([
            'business_id' => $businessId,
        ]);

        Schema::table('branches', function (Blueprint $table) {
            $table->unsignedBigInteger('business_id')->nullable(false)->change();
            $table->foreign('business_id')
                ->references('id')
                ->on('businesses')
                ->restrictOnDelete();
            $table->index('business_id');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('branches', function (Blueprint $table) {
            $table->dropForeign(['business_id']);
            $table->dropIndex(['business_id']);
            $table->dropColumn('business_id');
        });
    }
};