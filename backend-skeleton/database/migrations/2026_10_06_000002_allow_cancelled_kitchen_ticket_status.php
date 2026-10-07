<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Database\Schema\Blueprint;

return new class extends Migration
{
    public function up(): void
    {
        if (in_array(DB::getDriverName(), ['mysql', 'mariadb'], true)) {
            DB::statement("ALTER TABLE kitchen_tickets MODIFY COLUMN status ENUM('new', 'preparing', 'ready', 'completed', 'cancelled') NOT NULL DEFAULT 'new'");
        }
        if (DB::getDriverName() === 'sqlite') {
            // SQLite enforces the enum with a CHECK constraint. Rebuild the
            // column to permit cancelled tickets in the test database.
            Schema::table('kitchen_tickets', function (Blueprint $table) {
                $table->enum('status', ['new', 'preparing', 'ready', 'completed', 'cancelled'])
                    ->default('new')->change();
            });
        }
    }

    public function down(): void
    {
        if (DB::getDriverName() === 'sqlite') {
            DB::table('kitchen_tickets')->where('status', 'cancelled')->update(['status' => 'completed']);
            Schema::table('kitchen_tickets', function (Blueprint $table) {
                $table->enum('status', ['new', 'preparing', 'ready', 'completed'])
                    ->default('new')->change();
            });
        }
        if (in_array(DB::getDriverName(), ['mysql', 'mariadb'], true)) {
            DB::table('kitchen_tickets')->where('status', 'cancelled')->update(['status' => 'completed']);
            DB::statement("ALTER TABLE kitchen_tickets MODIFY COLUMN status ENUM('new', 'preparing', 'ready', 'completed') NOT NULL DEFAULT 'new'");
        }
    }
};
