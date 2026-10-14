<?php

namespace App\Services;

use App\Models\Unit;

class UnitConversionService
{
    public function convert(float $quantity, Unit $from, Unit $to): float
    {
        if ($from->id === $to->id) return $quantity;
        $standard = ['g' => ['mass', 1], 'kg' => ['mass', 1000], 'ml' => ['volume', 1], 'l' => ['volume', 1000], 'pc' => ['piece', 1], 'pcs' => ['piece', 1]];
        $a = $standard[strtolower($from->abbreviation)] ?? null;
        $b = $standard[strtolower($to->abbreviation)] ?? null;
        abort_unless($a && $b && $a[0] === $b[0], 422, 'Units must measure the same dimension (mass, volume or pieces).');
        return $quantity * $a[1] / $b[1];
    }
}
