<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('cash_drawer_events', function (Blueprint $table) {
            $table->id();
            $table->foreignId('business_id')->constrained()->restrictOnDelete();
            $table->foreignId('branch_id')->constrained()->restrictOnDelete();
            $table->foreignId('user_id')->constrained()->restrictOnDelete();
            $table->uuid('event_uuid');
            $table->string('source', 20);
            $table->foreignId('order_id')->nullable()->constrained()->restrictOnDelete();
            $table->string('reason', 255);
            $table->string('status', 30);
            // These are untrusted device timestamps, kept separate from receipt time.
            $table->string('device_requested_at', 40);
            $table->string('device_finished_at', 40)->nullable();
            $table->timestamps();
            $table->unique(['user_id', 'event_uuid']);
            $table->index(['business_id', 'branch_id', 'created_at']);
            $table->index(['order_id', 'source']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('cash_drawer_events');
    }
};
