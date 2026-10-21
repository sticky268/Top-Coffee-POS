<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('products', function (Blueprint $table) {
            $table->json('combo_slots')->nullable();
        });
        Schema::table('order_items', function (Blueprint $table) {
            $table->json('menu_configuration')->nullable();
            $table->text('variant_name')->nullable()->change();
        });
        Schema::table('modifier_groups', fn (Blueprint $table) => $table->boolean('is_active')->default(true));
        Schema::create('menu_discounts', function (Blueprint $table) {
            $table->id();
            $table->foreignId('business_id')->constrained();
            $table->foreignId('branch_id')->nullable()->constrained();
            $table->string('name', 120);
            $table->string('type', 16);
            $table->decimal('value', 10, 2);
            $table->date('starts_on')->nullable();
            $table->date('ends_on')->nullable();
            $table->boolean('is_active')->default(true);
            $table->boolean('requires_manager')->default(false);
            $table->timestamps();
            $table->index(['business_id', 'branch_id', 'is_active']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('menu_discounts');
        Schema::table('modifier_groups', fn (Blueprint $table) => $table->dropColumn('is_active'));
        Schema::table('order_items', fn (Blueprint $table) => $table->dropColumn('menu_configuration'));
        Schema::table('products', fn (Blueprint $table) => $table->dropColumn('combo_slots'));
    }
};
