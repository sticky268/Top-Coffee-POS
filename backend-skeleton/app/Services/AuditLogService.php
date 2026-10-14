<?php

namespace App\Services;

use App\Models\AuditLog;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;

class AuditLogService
{
    /**
     * Record a user action in the audit log.
     */
    public function record(
        Request $request,
        string $action,
        ?Model $auditable = null,
        ?array $oldValues = null,
        ?array $newValues = null,
    ): AuditLog {
        $branchId = $auditable instanceof \App\Models\Branch
            ? $auditable->getKey() : $auditable?->getAttribute('branch_id');
        $branchId ??= $request->input('branch_id');
        if ($branchId !== null) $newValues = ($newValues ?? []) + ['branch_id' => (int) $branchId];
        return AuditLog::create([
            'user_id' => $request->user()?->id,
            'action' => $action,
            'auditable_type' => $auditable?->getMorphClass(),
            'auditable_id' => $auditable?->getKey(),
            'old_values' => $oldValues,
            'new_values' => $newValues,
            'ip_address' => $request->ip(),
        ]);
    }
}