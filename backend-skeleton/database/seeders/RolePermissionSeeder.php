<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;
use Spatie\Permission\Models\Permission;
use Spatie\Permission\Models\Role;

class RolePermissionSeeder extends Seeder
{
    public function run(): void
    {
        $permissions = [
            'branches.view-all',
            'branches.manage',
            'users.manage',
            'products.manage',
            'orders.create', 'orders.view', 'orders.edit', 'orders.refund', 'orders.cancel',
            'inventory.view', 'inventory.adjust', 'inventory.manage',
            'reports.view',
            'audit.view',
            'expenses.manage',
            'kitchen.view', 'kitchen.update-status',
            'tables.manage',
            'customers.manage',
            'loyalty.manage',
            'settings.manage',
        ];

        foreach ($permissions as $permission) {
            Permission::firstOrCreate(['name' => $permission, 'guard_name' => 'web']);
        }

        $admin = Role::firstOrCreate(['name' => 'admin', 'guard_name' => 'web']);
        $admin->syncPermissions(Permission::all());

        $manager = Role::firstOrCreate(['name' => 'manager', 'guard_name' => 'web']);
        $manager->syncPermissions([
            'users.manage', 'products.manage', 'orders.view', 'orders.edit', 'orders.refund', 'orders.cancel',
            'inventory.view', 'inventory.adjust', 'inventory.manage', 'reports.view', 'audit.view',
            'expenses.manage', 'kitchen.view', 'kitchen.update-status', 'tables.manage', 'customers.manage', 'loyalty.manage', 'settings.manage',
        ]);

        $cashier = Role::firstOrCreate(['name' => 'cashier', 'guard_name' => 'web']);
        $cashier->syncPermissions([
            'orders.create', 'orders.view', 'customers.manage', 'tables.manage', 'inventory.view',
        ]);

        $kitchen = Role::firstOrCreate(['name' => 'kitchen_staff', 'guard_name' => 'web']);
        $kitchen->syncPermissions([
            'kitchen.view', 'kitchen.update-status',
        ]);
    }
}
