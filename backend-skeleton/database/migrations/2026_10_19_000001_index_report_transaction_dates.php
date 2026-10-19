<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('payments', fn (Blueprint $t) => $t->index(['created_at', 'order_id'], 'payments_report_event_date'));
        Schema::table('payment_refunds', fn (Blueprint $t) => $t->index(['created_at', 'payment_id'], 'refunds_report_event_date'));
        Schema::table('cashier_shifts', fn (Blueprint $t) => $t->index(['branch_id', 'created_at', 'closed_at'], 'shifts_report_interval'));
    }

    public function down(): void
    {
        Schema::table('payments', fn (Blueprint $t) => $t->dropIndex('payments_report_event_date'));
        Schema::table('payment_refunds', fn (Blueprint $t) => $t->dropIndex('refunds_report_event_date'));
        Schema::table('cashier_shifts', fn (Blueprint $t) => $t->dropIndex('shifts_report_interval'));
    }
};
