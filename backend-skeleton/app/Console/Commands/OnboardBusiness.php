<?php

namespace App\Console\Commands;

use App\Models\{Business, Branch, User};
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Validator;
use Illuminate\Support\Str;
use Spatie\Permission\Models\Role;

class OnboardBusiness extends Command
{
    protected $signature = 'pos:onboard-business {name} {--owner=} {--email=} {--branch=Main} {--timezone=Asia/Phnom_Penh}';
    protected $description = 'Create an isolated business, first branch and owner with checkout controls enabled';

    public function handle(): int
    {
        $input = ['name' => $this->argument('name'), 'owner' => $this->option('owner'), 'email' => $this->option('email'),
            'branch' => $this->option('branch'), 'timezone' => $this->option('timezone')];
        $validator = Validator::make($input, ['name' => 'required|string|max:255', 'owner' => 'required|string|max:255',
            'email' => 'required|email|max:255|unique:users,email', 'branch' => 'required|string|max:255', 'timezone' => 'required|timezone']);
        if ($validator->fails()) {
            $this->error($validator->errors()->first());
            return self::FAILURE;
        }
        if (! Role::where('name', 'admin')->where('guard_name', 'web')->exists()) {
            $this->error('Initialize reviewed roles with RolePermissionSeeder before onboarding.');
            return self::FAILURE;
        }
        $password = $this->secret('Owner password (at least 12 characters)');
        $confirmation = $this->secret('Confirm owner password');
        if (! is_string($password) || strlen($password) < 12 || $password !== $confirmation) {
            $this->error('Passwords must match and contain at least 12 characters.');
            return self::FAILURE;
        }
        $ids = DB::transaction(function () use ($input, $password) {
            $business = Business::create(['name' => $input['name'], 'slug' => Str::slug($input['name']).'-'.Str::lower(Str::random(8)),
                'email' => $input['email'], 'is_active' => true, 'status' => 'trial', 'started_at' => now(), 'expires_at' => now()->addDays(30)]);
            $business->forceFill(['require_cash_shift' => true, 'require_manager_controls' => true, 'manager_discount_percent' => 10])->save();
            $branch = Branch::create(['business_id' => $business->id, 'name' => $input['branch'], 'code' => 'B'.$business->id.'-01', 'timezone' => $input['timezone'], 'is_active' => true]);
            $owner = User::create(['business_id' => $business->id, 'name' => $input['owner'], 'email' => $input['email'], 'password' => $password, 'is_active' => true]);
            $owner->assignRole('admin');
            $owner->branches()->attach($branch->id, ['is_primary' => true]);
            DB::table('audit_logs')->insert(['business_id' => $business->id, 'user_id' => $owner->id,
                'action' => 'business.onboarded', 'new_values' => json_encode(['source' => 'console', 'branch_id' => $branch->id]), 'created_at' => now(), 'updated_at' => now()]);
            return ['business_id' => $business->id, 'branch_id' => $branch->id, 'owner_id' => $owner->id];
        });
        $this->line(json_encode($ids));
        $this->info('30-day trial created. Owner can sign in and create staff; no demo catalog or shared account created.');
        return self::SUCCESS;
    }
}
