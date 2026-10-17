<?php

namespace App\Http\Controllers;

use App\Services\OperationsHealthReport;
use Illuminate\Http\{JsonResponse, Request};

class OperationsHealthController
{
    public function __invoke(Request $request, OperationsHealthReport $health): JsonResponse
    {
        $expected = config('operations.health_token');
        if (! is_string($expected) || strlen($expected) < 32 || ! hash_equals($expected, (string) $request->bearerToken())) {
            return response()->json(['message' => 'Unauthorized.'], 401)->header('Cache-Control', 'no-store');
        }
        $report = $health->report();
        return response()->json($report, $report['healthy'] ? 200 : 503)->header('Cache-Control', 'no-store');
    }
}
