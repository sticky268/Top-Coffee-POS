<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    private array $tables = ['categories', 'products', 'customers', 'suppliers', 'expense_categories', 'modifier_groups', 'audit_logs'];

    public function up(): void
    {
        foreach ($this->tables as $name) {
            Schema::table($name, function (Blueprint $table) {
                $table->foreignId('business_id')->nullable()->constrained()->restrictOnDelete();
                $table->index('business_id');
            });
        }
        $businesses = DB::table('businesses')->pluck('id');
        $onlyBusiness = $businesses->count() === 1 ? $businesses->first() : null;
        foreach ($this->tables as $table) {
            DB::table($table)->orderBy('id')->chunkById(200, function ($rows) use ($table, $onlyBusiness) {
                foreach ($rows as $row) {
                    $owners = $this->owners($table, $row)->filter()->unique()->values();
                    $owner = $owners->count() === 1 ? $owners->first() : ($owners->isEmpty() ? $onlyBusiness : null);
                    if ($owner !== null) DB::table($table)->where('id', $row->id)->update(['business_id' => $owner]);
                }
            });
        }
        Schema::table('products', function (Blueprint $table) {
            $table->dropUnique('products_sku_unique');
            $table->unique(['business_id', 'sku']);
        });
    }

    private function owners(string $table, object $row): \Illuminate\Support\Collection
    {
        $owners = collect();
        if (isset($row->branch_id)) $owners->push(DB::table('branches')->where('id', $row->branch_id)->value('business_id'));
        $links = match ($table) {
            'categories' => DB::table('products as p')->join('branch_product as bp', 'bp.product_id', '=', 'p.id')->where('p.category_id', $row->id),
            'products' => DB::table('branch_product as bp')->where('bp.product_id', $row->id),
            'customers' => DB::table('orders as bp')->where('bp.customer_id', $row->id),
            'suppliers' => DB::table('purchases as bp')->where('bp.supplier_id', $row->id),
            'expense_categories' => DB::table('expenses as bp')->where('bp.expense_category_id', $row->id),
            'modifier_groups' => DB::table('product_modifier_group as pm')->join('branch_product as bp', 'bp.product_id', '=', 'pm.product_id')->where('pm.modifier_group_id', $row->id),
            default => null,
        };
        if ($links) $owners = $owners->merge($links->join('branches as b', 'b.id', '=', 'bp.branch_id')->pluck('b.business_id'));
        if ($table === 'products') $owners->push(DB::table('categories')->where('id', $row->category_id)->value('business_id'));
        if ($table === 'audit_logs') $owners->push(DB::table('users')->where('id', $row->user_id)->value('business_id'));
        return $owners;
    }

    public function down(): void
    {
        // Ownership is security metadata. Reverting to global access is not safe,
        // and tenant-specific SKUs may now duplicate across businesses.
        throw new RuntimeException('Restore a verified backup to revert business ownership.');
    }
};
