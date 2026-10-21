<?php

namespace App\Services;

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

class TenantIntegrity
{
    public const OWNED_TABLES = ['categories', 'products', 'customers', 'suppliers', 'expense_categories', 'modifier_groups', 'menu_discounts', 'audit_logs'];

    public function report(): array
    {
        $unowned = [];
        foreach (self::OWNED_TABLES as $table) {
            if (! Schema::hasColumn($table, 'business_id')) return ['ready' => false, 'error' => 'Business ownership migration is required.'];
            $unowned[$table] = DB::table($table)->whereNull('business_id')->count();
        }
        $links = [
            'menu_discount_branch' => ['menu_discounts', 'branches', 'branch_id', 'id', 'a.business_id', 'b.business_id'],
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
        foreach (['orders' => 'user_id', 'cashier_shifts' => 'user_id', 'stock_movements' => 'created_by'] as $table => $actor) {
            $mismatches[$table.'_actor'] = DB::table($table.' as a')->join('branches as b', 'b.id', '=', 'a.branch_id')
                ->join('users as u', 'u.id', '=', 'a.'.$actor)->whereColumn('u.business_id', '!=', 'b.business_id')->count();
        }
        $mismatches['recipe_ingredient_branch'] = DB::table('recipe_items as r')->join('ingredients as i', 'i.id', '=', 'r.ingredient_id')
            ->whereColumn('r.branch_id', '!=', 'i.branch_id')->count();
        $mismatches['payment_shift_owner'] = DB::table('payments as p')->join('orders as o', 'o.id', '=', 'p.order_id')
            ->join('cashier_shifts as s', 's.id', '=', 'p.shift_id')->where(function ($q) {
                $q->whereColumn('s.branch_id', '!=', 'o.branch_id')->orWhereColumn('s.user_id', '!=', 'p.processed_by');
            })->count();
        $mismatches['order_product'] = DB::table('order_items as i')->join('orders as o', 'o.id', '=', 'i.order_id')
            ->join('branches as b', 'b.id', '=', 'o.branch_id')->join('products as p', 'p.id', '=', 'i.product_id')
            ->whereColumn('p.business_id', '!=', 'b.business_id')->count();
        $mismatches['product_modifier_group'] = DB::table('product_modifier_group as pm')->join('products as p', 'p.id', '=', 'pm.product_id')
            ->join('modifier_groups as m', 'm.id', '=', 'pm.modifier_group_id')->whereColumn('p.business_id', '!=', 'm.business_id')->count();
        return ['ready' => array_sum($unowned) === 0 && array_sum($mismatches) === 0, 'unowned' => $unowned, 'cross_business_links' => $mismatches];
    }
}
