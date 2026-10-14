<?php

namespace App\Console\Commands;

use App\Models\Business;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

class CheckoutControls extends Command
{
    protected $signature = 'pos:checkout-controls {business : Business ID} {--enable : Enable cash shifts and manager approval} {--discount-percent=10 : Discounts above this percentage require manager sign-in}';
    protected $description = 'Inspect or enable checkout safeguards for one business';

    public function handle(): int
    {
        $id = filter_var($this->argument('business'), FILTER_VALIDATE_INT);
        $percent = filter_var($this->option('discount-percent'), FILTER_VALIDATE_FLOAT);
        if (! $id || $percent === false || $percent < 0 || $percent > 100) {
            $this->error('Use a valid business ID and a percentage from 0 to 100.');
            return self::FAILURE;
        }
        $business = Business::findOrFail($id);
        if ($this->option('enable')) {
            DB::transaction(function () use ($business, $percent) {
                $business->forceFill(['require_cash_shift' => true, 'require_manager_controls' => true, 'manager_discount_percent' => $percent])->save();
                DB::table('audit_logs')->insert(['business_id' => $business->id, 'action' => 'business.checkout_controls_enabled',
                    'new_values' => json_encode(['source' => 'console', 'discount_percent' => $percent]), 'created_at' => now(), 'updated_at' => now()]);
            });
        }
        $this->line(json_encode($business->only(['id', 'require_cash_shift', 'require_manager_controls', 'manager_discount_percent'])));
        return self::SUCCESS;
    }
}
