<?php

namespace App\Services\Reports;

/** Integer-only decimal parsing and largest-remainder allocation. */
final class ReportAllocation
{
    public static function micros(string|int $value): int
    {
        if (! preg_match('/^(-?)(\d+)(?:\.(\d{1,6}))?$/D', (string) $value, $m)) {
            throw new \InvalidArgumentException('Invalid historical cost.');
        }
        return ($m[1] === '-' ? -1 : 1) * ((int) $m[2] * 1000000 + (int) str_pad($m[3] ?? '', 6, '0'));
    }

    public static function decimal(int $value): string
    {
        return ($value < 0 ? '-' : '').intdiv(abs($value), 1000000).'.'.str_pad((string) (abs($value) % 1000000), 6, '0', STR_PAD_LEFT);
    }

    /** floor(a*b/d), remainder, without overflowing the intermediate product. */
    public static function quotient(int $a, int $b, int $d): array
    {
        if ($a < 0 || $b < 0 || $d <= 0) throw new \InvalidArgumentException('Invalid allocation.');
        $q = 0; $r = 0; $whole = intdiv($a, $d); $part = $a % $d;
        while ($b > 0) {
            if ($b % 2 === 1) {
                $q += $whole; $r += $part;
                if ($r >= $d) { $q++; $r -= $d; }
            }
            $b = intdiv($b, 2);
            if ($b > 0) {
                $whole *= 2; $part *= 2;
                if ($part >= $d) { $whole++; $part -= $d; }
            }
        }
        return [$q, $r];
    }

    public static function ratio(int $a, int $b, int $d): int
    {
        if ($d <= 0) return 0;
        [$q, $r] = self::quotient(abs($a), abs($b), $d);
        if ($r >= intdiv($d + 1, 2)) $q++;
        return ($a < 0 xor $b < 0) ? -$q : $q;
    }

    /** Stable input order breaks equal remainders; allocations sum exactly. */
    public static function split(int $amount, array $weights): array
    {
        $sum = array_sum($weights);
        if ($sum <= 0) $weights = array_fill_keys(array_keys($weights), 1);
        $sum = array_sum($weights);
        if ($sum === 0) return [];
        $parts = $remainders = [];
        foreach ($weights as $key => $weight) {
            [$parts[$key], $remainders[$key]] = self::quotient(abs($amount), $weight, $sum);
        }
        $left = abs($amount) - array_sum($parts);
        arsort($remainders, SORT_NUMERIC);
        foreach ($remainders as $key => $_) {
            if ($left-- <= 0) break;
            $parts[$key]++;
        }
        return array_map(fn ($v) => $amount < 0 ? -$v : $v, $parts);
    }
}
