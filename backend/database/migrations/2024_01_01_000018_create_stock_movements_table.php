<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // Authoritative ledger. ingredients.current_stock is a cache derived from this table.
        Schema::create('stock_movements', function (Blueprint $table) {
            $table->id();
            $table->foreignId('ingredient_id')->constrained()->restrictOnDelete();
            $table->foreignId('branch_id')->constrained()->restrictOnDelete();
            $table->enum('type', ['purchase', 'sale_deduction', 'adjustment', 'wastage']);
            $table->decimal('quantity', 14, 3); // positive for additions, negative for deductions
            $table->decimal('balance_after', 14, 3); // running balance snapshot, for auditability
            $table->string('reference_type')->nullable(); // e.g. App\Models\Order, App\Models\Purchase
            $table->unsignedBigInteger('reference_id')->nullable();
            $table->string('reason')->nullable(); // required (enforced in app layer) for adjustment/wastage
            $table->foreignId('created_by')->constrained('users')->restrictOnDelete();
            $table->timestamps();

            $table->index(['ingredient_id', 'created_at']);
            $table->index(['reference_type', 'reference_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('stock_movements');
    }
};
