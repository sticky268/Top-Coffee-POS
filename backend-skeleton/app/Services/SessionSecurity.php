<?php

namespace App\Services;

use App\Models\AuditLog;
use App\Models\User;
use Illuminate\Http\Request;

class SessionSecurity
{
    /** Explicit ownership is essential: login failures have no authenticated actor. */
    public function audit(Request $request, string $action, ?User $subject, array $details = []): void
    {
        if (! $subject) return; // Do not persist arbitrary attacker-supplied identities.
        $event = new AuditLog([
            'user_id' => $subject->id, 'action' => $action,
            'auditable_type' => $subject->getMorphClass(), 'auditable_id' => $subject->id,
            'new_values' => $details, 'ip_address' => $request->ip(),
        ]);
        $event->business_id = $subject->business_id;
        $event->save();
    }
}
