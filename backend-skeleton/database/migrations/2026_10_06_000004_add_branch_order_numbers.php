<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('orders', function (Blueprint $table) {
            $table->unsignedBigInteger('order_number')->nullable()->after('branch_id');
        });

        $branchIds = DB::table('orders')
            ->select('branch_id')
            ->distinct()
            ->orderBy('branch_id')
            ->pluck('branch_id');

        foreach ($branchIds as $branchId) {
            $number = 1;

            DB::table('orders')
                ->where('branch_id', $branchId)
                ->orderBy('id')
                ->pluck('id')
                ->each(function ($orderId) use (&$number): void {
                    DB::table('orders')
                        ->where('id', $orderId)
                        ->update(['order_number' => $number++]);
                });
        }

        Schema::table('orders', function (Blueprint $table) {
            $table->unique(
                ['branch_id', 'order_number'],
                'orders_branch_order_number_unique'
            );
        });
    }

    public function down(): void
    {
        Schema::table('orders', function (Blueprint $table) {
            $table->dropUnique('orders_branch_order_number_unique');
            $table->dropColumn('order_number');
        });
    }
};
