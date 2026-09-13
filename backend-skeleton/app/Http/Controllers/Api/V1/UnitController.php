<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\Unit;
use Illuminate\Http\Request;

class UnitController extends Controller
{
    public function index(Request $request)
    {
        if (! $request->user()->can('inventory.view')) {
            return response()->json([
                'success' => false,
                'message' => 'Forbidden',
            ], 403);
        }

        $units = Unit::query()
            ->orderBy('name')
            ->get([
                'id',
                'name',
                'abbreviation',
                'base_unit_id',
                'conversion_factor',
            ]);

        return response()->json([
            'success' => true,
            'data' => $units,
        ]);
    }
}