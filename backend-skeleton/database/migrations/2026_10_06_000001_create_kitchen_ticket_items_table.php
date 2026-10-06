<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('kitchen_ticket_items', function (Blueprint $table) {
            $table->id();
            $table->foreignId('kitchen_ticket_id')->constrained('kitchen_tickets')->cascadeOnDelete();
            $table->foreignId('order_item_id')->constrained('order_items')->cascadeOnDelete();
            $table->unsignedInteger('quantity');
            $table->timestamps();
            $table->unique(['kitchen_ticket_id', 'order_item_id']);
        });

        // Historical tickets did not identify individual items. Attach the
        // current bill to the first ticket for each order, without inventing
        // additional kitchen submissions for any later legacy tickets.
        DB::table('kitchen_tickets')->orderBy('id')->chunkById(200, function ($tickets) {
            foreach ($tickets as $ticket) {
                $firstTicketId = DB::table('kitchen_tickets')
                    ->where('order_id', $ticket->order_id)->min('id');
                if ((int) $ticket->id !== (int) $firstTicketId) {
                    continue;
                }
                $items = DB::table('order_items')
                    ->where('order_id', $ticket->order_id)->get(['id', 'quantity']);
                foreach ($items as $item) {
                    DB::table('kitchen_ticket_items')->insert([
                        'kitchen_ticket_id' => $ticket->id,
                        'order_item_id' => $item->id,
                        'quantity' => $item->quantity,
                        'created_at' => now(),
                        'updated_at' => now(),
                    ]);
                }
            }
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('kitchen_ticket_items');
    }
};
