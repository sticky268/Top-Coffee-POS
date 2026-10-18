<?php

namespace App\Services\Reports;

/** Exact two-decimal money at the report boundary; no binary floating point. */
final class ReportMoney
{
    public static function cents(string|int $amount): int
    {
        if (! preg_match('/^(-?)(\d+)(?:\.(\d{1,2}))?$/D', (string) $amount, $parts)) {
            throw new \InvalidArgumentException('Invalid report money value.');
        }
        $value = (int) $parts[2] * 100 + (int) str_pad($parts[3] ?? '', 2, '0');
        return ($parts[1] === '-' ? -1 : 1) * $value;
    }

    public static function decimal(int $cents): string
    {
        return ($cents < 0 ? '-' : '').intdiv(abs($cents), 100).'.'.str_pad((string) (abs($cents) % 100), 2, '0', STR_PAD_LEFT);
    }

    public static function divide(int $numerator, int $denominator): int
    {
        if ($denominator <= 0) return 0;
        $rounded = intdiv(abs($numerator), $denominator);
        if (abs($numerator) % $denominator >= intdiv($denominator + 1, 2)) $rounded++;
        return $numerator < 0 ? -$rounded : $rounded;
    }

    public static function comparison(int $current, int $previous): array
    {
        return [
            'previous' => self::decimal($previous),
            'delta' => self::decimal($current - $previous),
            'percent' => $previous === 0 ? null : self::decimal(self::divide(($current - $previous) * 10000, abs($previous))),
            'status' => $previous === 0 ? ($current === 0 ? 'unchanged' : 'new') : 'comparable',
        ];
    }

    public static function sql(string $column): string
    {
        // DECIMAL on MySQL, integer SUM on SQLite as well. Each source amount is scale 2.
        return "CAST(ROUND(COALESCE($column, 0) * 100, 0) AS SIGNED)";
    }
}
