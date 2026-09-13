<?php

namespace App\Http\Controllers\Api\V1;

use App\Models\ExpenseCategory;
use App\Http\Controllers\Controller;
use Illuminate\Http\Request;

class ExpenseCategoryController extends Controller
{
    public function index(Request $request)
    {
        if (! $request->user()->can('expenses.manage')) {
            return response()->json([
                'success' => false,
                'message' => 'Forbidden',
            ], 403);
        }

        $categories = ExpenseCategory::query()
            ->orderBy('name')
            ->get(['id', 'name']);

        return response()->json([
            'success' => true,
            'data' => $categories,
        ]);
    }
}