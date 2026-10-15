<?php

namespace App\Console\Commands;

use App\Models\Business;
use Illuminate\Console\Command;
use Throwable;

class BusinessSettingsCheck extends Command
{
    protected $signature = 'pos:business-settings-check {--json : Safe check results only}';
    protected $description = 'Fail closed unless pilot business safeguards are enforceable';

    public function handle(): int
    {
        $checks = ['cash_only_default' => config('payments.allowed_methods') === ['cash']];
        try {
            $businesses = Business::where('is_active', true)->get();
            $checks['active_businesses_present'] = $businesses->isNotEmpty();
            $checks['cash_shift_required'] = $businesses->isNotEmpty() && $businesses->every(fn ($b) => $b->require_cash_shift === true);
            $checks['manager_controls_required'] = $businesses->isNotEmpty() && $businesses->every(fn ($b) => $b->require_manager_controls === true);
            // Strict pilot policy: all non-zero discounts require a manager session.
            $checks['cashier_discount_limit_zero'] = $businesses->isNotEmpty() && $businesses->every(fn ($b) => is_numeric($b->manager_discount_percent) && (float) $b->manager_discount_percent === 0.0);
            $checks += app(\App\Services\ManagerPinReadiness::class)->checks($businesses->modelKeys());
        } catch (Throwable) {
            $checks['business_settings_readable'] = false;
        }
        $report = ['ready' => ! in_array(false, $checks, true), 'checks' => $checks];
        if ($this->option('json')) $this->line(json_encode($report, JSON_THROW_ON_ERROR));
        else {
            $this->table(['Check', 'Result'], array_map(fn ($k, $v) => [$k, $v ? 'PASS' : 'FAIL'], array_keys($checks), $checks));
            if (! $report['ready']) $this->error('Resolve failed business settings or enroll an authorized manager PIN for every active branch.');
        }
        return $report['ready'] ? self::SUCCESS : self::FAILURE;
    }
}
