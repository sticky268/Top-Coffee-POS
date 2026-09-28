<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\AuditLog;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;

class AuditLogController extends Controller
{
    public function index(Request $request)
    {
        if (! $request->user()->can('audit.view')) {
            return response()->json([
                'success' => false,
                'message' => 'You do not have permission to view audit logs',
            ], 403);
        }

        $validator = Validator::make($request->query(), [
            'action' => 'nullable|string|max:255',
            'user_id' => 'nullable|integer|exists:users,id',
            'auditable_type' => 'nullable|string|max:255',
            'search' => 'nullable|string|max:255',
            'from' => 'nullable|date',
            'to' => 'nullable|date|after_or_equal:from',
            'per_page' => 'nullable|integer|min:1|max:100',
            'page' => 'nullable|integer|min:1',
        ]);

        if ($validator->fails()) {
            return response()->json([
                'success' => false,
                'message' => 'Validation failed',
                'errors' => $validator->errors(),
            ], 422);
        }

        $query = AuditLog::query()
            ->with('user:id,name,email')
            ->when($request->filled('action'), function ($query) use ($request) {
                $query->where('action', $request->input('action'));
            })
            ->when($request->filled('user_id'), function ($query) use ($request) {
                $query->where('user_id', (int) $request->input('user_id'));
            })
            ->when($request->filled('auditable_type'), function ($query) use ($request) {
                $query->where('auditable_type', $request->input('auditable_type'));
            })
            ->when($request->filled('search'), function ($query) use ($request) {
                $search = trim($request->input('search'));

                $query->where(function ($query) use ($search) {
                    $query->where('action', 'like', "%{$search}%")
                        ->orWhere('auditable_type', 'like', "%{$search}%")
                        ->orWhereHas('user', function ($query) use ($search) {
                            $query->where('name', 'like', "%{$search}%")
                                ->orWhere('email', 'like', "%{$search}%");
                        });
                });
            })
            ->when($request->filled('from'), function ($query) use ($request) {
                $query->where('created_at', '>=', $request->input('from'));
            })
            ->when($request->filled('to'), function ($query) use ($request) {
                $query->where('created_at', '<=', $request->input('to'));
            });

        $perPage = (int) $request->input('per_page', 20);

        $logs = $query
            ->latest()
            ->paginate($perPage);

        return response()->json([
            'success' => true,
            'data' => $logs->map(fn (AuditLog $log) => [
                'id' => $log->id,
                'user_id' => $log->user_id,
                'user' => $log->user ? [
                    'id' => $log->user->id,
                    'name' => $log->user->name,
                    'email' => $log->user->email,
                ] : null,
                'action' => $log->action,
                'auditable_type' => $log->auditable_type,
                'auditable_id' => $log->auditable_id,
                'old_values' => $log->old_values,
                'new_values' => $log->new_values,
                'ip_address' => $log->ip_address,
                'created_at' => $log->created_at?->toIso8601String(),
            ]),
            'meta' => [
                'current_page' => $logs->currentPage(),
                'last_page' => $logs->lastPage(),
                'per_page' => $logs->perPage(),
                'total' => $logs->total(),
            ],
        ]);
    }
}