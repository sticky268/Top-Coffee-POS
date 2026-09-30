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
        Schema::table('users', function (Blueprint $table) {
            $table->unsignedBigInteger('business_id')->nullable()->after('id');
        });

        DB::table('users')->update([
            'business_id' => DB::table('businesses')
                ->where('slug', 'top-coffee')
                ->value('id'),
        ]);

        Schema::table('users', function (Blueprint $table) {
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
        Schema::table('users', function (Blueprint $table) {
            $table->dropForeign(['business_id']);
            $table->dropIndex(['business_id']);
            $table->dropColumn('business_id');
        });
    }
};