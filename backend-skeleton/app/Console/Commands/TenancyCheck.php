<?php

namespace App\Console\Commands;

use App\Services\TenantIntegrity;
use Illuminate\Console\Command;

class TenancyCheck extends Command
{
    protected $signature = 'pos:tenancy-check {--json}';
    protected $description = 'Read-only check for unresolved ownership and cross-business links';

    public function handle(TenantIntegrity $integrity): int
    {
        $result = $integrity->report();
        $this->line(json_encode($result, JSON_PRETTY_PRINT | JSON_THROW_ON_ERROR));
        return $result['ready'] ? self::SUCCESS : self::FAILURE;
    }
}
