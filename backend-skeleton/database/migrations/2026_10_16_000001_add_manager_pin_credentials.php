<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->string('manager_pin_hash')->nullable();
            $table->unsignedTinyInteger('manager_pin_failures')->default(0);
            $table->timestamp('manager_pin_locked_until')->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('users', fn (Blueprint $table) => $table->dropColumn([
            'manager_pin_hash', 'manager_pin_failures', 'manager_pin_locked_until',
        ]));
    }
};
