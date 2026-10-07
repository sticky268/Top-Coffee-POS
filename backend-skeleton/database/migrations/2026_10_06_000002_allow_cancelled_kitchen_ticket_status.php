<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    public function up(): void
    {
        if (in_array(DB::getDriverName(), ['mysql', 'mariadb'], true)) {
            DB::statement("ALTER TABLE kitchen_tickets MODIFY COLUMN status ENUM('new', 'preparing', 'ready', 'completed', 'cancelled') NOT NULL DEFAULT 'new'");
        }
        // SQLite stores Laravel enum columns as text, so no change is needed.
    }

    public function down(): void
    {
        if (in_array(DB::getDriverName(), ['mysql', 'mariadb'], true)) {
            DB::table('kitchen_tickets')->where('status', 'cancelled')->update(['status' => 'completed']);
            DB::statement("ALTER TABLE kitchen_tickets MODIFY COLUMN status ENUM('new', 'preparing', 'ready', 'completed') NOT NULL DEFAULT 'new'");
        }
    }
};
