<?php

namespace App\Services\Reports;

use Carbon\CarbonImmutable;

final class ReportPeriod
{
    public readonly string $from;
    public readonly string $to;
    public readonly string $previousFrom;
    public readonly string $previousTo;
    public readonly string $today;
    public readonly string $kind;

    public function __construct(array $input, string $timezone)
    {
        $today = CarbonImmutable::today($timezone);
        $this->today = $today->toDateString();
        $this->kind = $input['period'] ?? 'today';
        $from = $today;
        $to = $today;
        switch ($this->kind) {
            case 'yesterday': $from = $to = $today->subDay(); break;
            case 'week': $from = $today->startOfWeek(); break;
            case 'last7': $from = $today->subDays(6); break;
            case 'last30': $from = $today->subDays(29); break;
            case 'this_month': $from = $today->startOfMonth(); break;
            case 'last_month': $from = $today->subMonthNoOverflow()->startOfMonth(); $to = $from->endOfMonth(); break;
            case 'month':
                $from = CarbonImmutable::create($input['year'], $input['month'], 1, 0, 0, 0, $timezone);
                $to = $from->format('Y-m') === $today->format('Y-m') ? $today : $from->endOfMonth();
                break;
            case 'year':
                $from = CarbonImmutable::create($input['year'], 1, 1, 0, 0, 0, $timezone);
                $to = $from->year === $today->year ? $today : $from->endOfYear();
                break;
            case 'custom':
                $from = CarbonImmutable::parse($input['date_from'], $timezone)->startOfDay();
                $to = CarbonImmutable::parse($input['date_to'], $timezone)->startOfDay();
                break;
        }
        abort_if($to->lt($from) || $from->diffInDays($to->startOfDay()) >= 366, 422, 'Choose an ordered range of at most 366 days.');
        $this->from = $from->toDateString();
        $this->to = $to->toDateString();
        if (in_array($this->kind, ['month', 'last_month', 'this_month'], true)) {
            $previousFrom = $from->subMonthNoOverflow()->startOfMonth();
            $previousTo = $from->format('Y-m') === $today->format('Y-m')
                ? $previousFrom->day(min($today->day, $previousFrom->daysInMonth))
                : $previousFrom->endOfMonth();
        } elseif ($this->kind === 'year') {
            $previousFrom = $from->subYear();
            $previousTo = $from->year === $today->year ? $today->subYearNoOverflow() : $previousFrom->endOfYear();
        } elseif ($this->kind === 'week') {
            $previousFrom = $from->subWeek();
            $previousTo = $to->subWeek();
        } else {
            $days = (int) $from->diffInDays($to->startOfDay()) + 1;
            $previousFrom = $from->subDays($days);
            $previousTo = $from->subDay();
        }
        if (isset($input['comparison_from'], $input['comparison_to'])) {
            $previousFrom = CarbonImmutable::parse($input['comparison_from'], $timezone)->startOfDay();
            $previousTo = CarbonImmutable::parse($input['comparison_to'], $timezone)->startOfDay();
            abort_if($previousFrom->gt($previousTo) || $previousTo->gte($from) || $previousFrom->diffInDays($previousTo) >= 366, 422, 'Choose a previous comparison of at most 366 days before this selection.');
        }
        $this->previousFrom = $previousFrom->toDateString();
        $this->previousTo = $previousTo->toDateString();
    }

    public static function window(string $from, string $to, string $timezone): array
    {
        return [CarbonImmutable::parse($from, $timezone)->startOfDay()->utc()->toDateTimeString(),
            CarbonImmutable::parse($to, $timezone)->startOfDay()->addDay()->utc()->toDateTimeString()];
    }
}
