<?php

namespace App\Services;

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

class TenantIntegrity
{
    public const OWNED_TABLES = ['categories', 'products', 'customers', 'suppliers', 'expense_categories', 'modifier_groups', 'audit_logs'];

    public function report(): array
    {
        $unowned = [];
        foreach (self::OWNED_TABLES as $table) {
            if (! Schema::hasColumn($table, 'business_id')) return ['ready' => false, 'error' => 'Business ownership migration is required.'];
            $unowned[$table] = DB::table($table)->whereNull('business_id')->count();
        }
        $links = [
            'category_branch' => ['categories', 'branches', 'branch_id', 'id', 'a.business_id', 'b.business_id'],
            'product_category' => ['products', 'categories', 'category_id', 'id', 'a.business_id', 'b.business_id'],
            'customer_branch' => ['customers', 'branches', 'branch_id', 'id', 'a.business_id', 'b.business_id'],
            'supplier_branch' => ['suppliers', 'branches', 'branch_id', 'id', 'a.business_id', 'b.business_id'],
            'audit_actor' => ['audit_logs', 'users', 'user_id', 'id', 'a.business_id', 'b.business_id'],
        ];
        $mismatches = [];
        foreach ($links as $name => [$left, $right, $key, $id, $ownerA, $ownerB]) {
            $mismatches[$name] = DB::table($left.' as a')->join($right.' as b', 'a.'.$key, '=', 'b.'.$id)->whereColumn($ownerA, '!=', $ownerB)->count();
        }
        $branches = [
            'product_availability' => ['branch_product', 'product_id', 'products'],
            'order_customer' => ['orders', 'customer_id', 'customers'],
            'purchase_supplier' => ['purchases', 'supplier_id', 'suppliers'],
            'expense_category' => ['expenses', 'expense_category_id', 'expense_categories'],
            'staff_assignment' => ['user_branch', 'user_id', 'users'],
            'loyalty_customer' => ['loyalty_transactions', 'customer_id', 'customers'],
            'recipe_product' => ['recipe_items', 'product_id', 'products'],
        ];
        foreach ($branches as $name => [$left, $key, $right]) {
            $mismatches[$name] = DB::table($left.' as a')->join('branches as b', 'b.id', '=', 'a.branch_id')
                ->join($right.' as r', 'r.id', '=', 'a.'.$key)->whereColumn('r.business_id', '!=', 'b.business_id')->count();
        }
        $mismatches['order_product'] = DB::table('order_items as i')->join('orders as o', 'o.id', '=', 'i.order_id')
            ->join('branches as b', 'b.id', '=', 'o.branch_id')->join('products as p', 'p.id', '=', 'i.product_id')
            ->whereColumn('p.business_id', '!=', 'b.business_id')->count();
        $mismatches['product_modifier_group'] = DB::table('product_modifier_group as pm')->join('products as p', 'p.id', '=', 'pm.product_id')
            ->join('modifier_groups as m', 'm.id', '=', 'pm.modifier_group_id')->whereColumn('p.business_id', '!=', 'm.business_id')->count();
        return ['ready' => array_sum($unowned) === 0 && array_sum($mismatches) === 0, 'unowned' => $unowned, 'cross_business_links' => $mismatches];
    }
}
