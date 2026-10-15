<?php

namespace App\Console\Commands;

use App\Models\{AuditLog, User};
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

class RevokeDevice extends Command
{
    protected $signature = 'pos:revoke-device {user : User ID} {device : Installation UUID} {--reason= : Incident reference, not personal data}';
    protected $description = 'Immediately revoke one user installation and append an audit event';

    public function handle(): int
    {
        $id = filter_var($this->argument('user'), FILTER_VALIDATE_INT);
        $device = strtolower((string) $this->argument('device'));
        $reason = trim((string) $this->option('reason'));
        if (! $id || ! Str::isUuid($device) || ! preg_match('/^[A-Za-z0-9 .:_-]{3,120}$/D', $reason)) {
            $this->error('Use a user ID, installation UUID and a 3-120 character incident reference.');
            return self::FAILURE;
        }
        $count = DB::transaction(function () use ($id, $device, $reason) {
            $user = User::lockForUpdate()->findOrFail($id);
            $count = $user->tokens()->whereRaw('LOWER(name) = ?', ['device:'.$device])->delete();
            $event = new AuditLog(['user_id' => $user->id, 'action' => 'auth.device_revoked',
                'auditable_type' => $user->getMorphClass(), 'auditable_id' => $user->id,
                'new_values' => ['source' => 'console', 'incident' => $reason, 'device_id' => $device, 'revoked' => $count]]);
            $event->business_id = $user->business_id;
            $event->save();
            return $count;
        });
        $this->info('Revoked '.$count.' token(s). Other installations are unchanged.');
        return self::SUCCESS;
    }
}
