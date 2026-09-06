<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('sync_logs', function (Blueprint $table) {
            $table->id();
            $table->string('device_id');
            $table->uuid('order_uuid'); // matches orders.uuid (the idempotency key)
            $table->foreignId('order_id')->nullable()->constrained()->nullOnDelete();
            $table->enum('status', ['accepted', 'duplicate_ignored', 'conflict', 'rejected']);
            $table->text('note')->nullable();
            $table->timestamp('attempted_at');
            $table->timestamps();

            $table->index('order_uuid');
            $table->index('device_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('sync_logs');
    }
};
