<?php

namespace App\Console\Commands;

use Illuminate\Console\Command;
use App\Services\OperationsHealthReport;

class OperationsHealth extends Command
{
    protected $signature = 'pos:operations-health {--json : Return only safe check names and booleans}';
    protected $description = 'Read-only DB/cache/disk, failed-job and security-event health signals';

    public function handle(): int
    {
        $report = app(OperationsHealthReport::class)->report();
        $checks = $report['checks'];
        $healthy = $report['healthy'];
        if ($this->option('json')) $this->line(json_encode($report, JSON_THROW_ON_ERROR));
        else $this->table(['Check', 'Result'], array_map(fn ($name, $pass) => [$name, $pass ? 'PASS' : 'FAIL'], array_keys($checks), $checks));
        return $healthy ? self::SUCCESS : self::FAILURE;
    }
}
