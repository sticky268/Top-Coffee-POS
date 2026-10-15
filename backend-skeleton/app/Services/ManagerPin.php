<?php

namespace App\Services;

use App\Models\{Business, Order, User};
use Illuminate\Http\Request;
use Illuminate\Support\Facades\{DB, Hash};

class ManagerPin
{
    public function required(User $user): bool
    {
        return config('app.env') === 'production' || Business::whereKey($user->business_id)->value('require_manager_controls') == true;
    }

    public function manager(User $user): bool
    {
        return $user->is_active && $user->business?->is_active && $user->hasAnyRole(['admin', 'manager']);
    }

    public function configured(User $user): bool
    {
        return is_string($user->manager_pin_hash) && password_get_info($user->manager_pin_hash)['algo'] !== null;
    }

    private function pepper(User $user, string $pin): string
    {
        $key = (string) config('app.key');
        if (str_starts_with($key, 'base64:')) $key = base64_decode(substr($key, 7), true) ?: '';
        if (strlen($key) < 32) throw new \RuntimeException('Application encryption key must be configured.');
        return hash_hmac('sha256', 'manager-pin:v1:'.$user->business_id.':'.$user->id.':'.$pin, $key);
    }

    private function failure(Request $request, User $user, string $purpose): array
    {
        $failures = (int) $user->manager_pin_failures + 1;
        $user->forceFill(['manager_pin_failures' => min(5, $failures),
            'manager_pin_locked_until' => $failures >= 5 ? now()->addMinutes(15) : null])->save();
        app(AuditLogService::class)->record($request, 'auth.manager_pin_failed', $user, null,
            ['purpose' => $purpose, 'locked' => $failures >= 5]);
        return ['status' => $failures >= 5 ? 429 : 403,
            'message' => $failures >= 5 ? 'Manager PIN locked for 15 minutes.' : 'Manager verification failed.'];
    }

    private function lockStatus(User $user): ?array
    {
        if ($user->manager_pin_locked_until?->isFuture()) {
            return ['status' => 429, 'message' => 'Manager PIN is temporarily locked. Wait 15 minutes from the last lockout.'];
        }
        if ($user->manager_pin_locked_until !== null) {
            $user->forceFill(['manager_pin_failures' => 0, 'manager_pin_locked_until' => null])->save();
        }
        return null;
    }

    public function enroll(Request $request): void
    {
        $request->validate(['expected_user_id' => 'required|integer', 'current_password' => 'required|string|max:4096',
            'pin' => ['required', 'string', 'regex:/^[0-9]{6,12}$/D', 'confirmed']]);
        abort_unless($request->integer('expected_user_id') === $request->user()->id, 403, 'Session changed.');
        $pin = $request->string('pin')->toString();
        abort_if(preg_match('/^(.)\1+$/D', $pin) || str_contains('01234567890123456789', $pin)
            || str_contains('98765432109876543210', $pin), 422, 'Choose a PIN without repeated or sequential digits.');
        $result = DB::transaction(function () use ($request, $pin) {
            $user = User::whereKey($request->user()->id)->lockForUpdate()->firstOrFail();
            abort_unless($this->manager($user), 403, 'A manager must sign in.');
            if ($locked = $this->lockStatus($user)) return $locked;
            if (! Hash::check($request->input('current_password'), $user->password)) return $this->failure($request, $user, 'enrollment');
            $user->forceFill(['manager_pin_hash' => Hash::make($this->pepper($user, $pin)),
                'manager_pin_failures' => 0, 'manager_pin_locked_until' => null])->save();
            app(AuditLogService::class)->record($request, 'auth.manager_pin_changed', $user, null, ['source' => 'own_password_verified']);
            return ['status' => 200];
        });
        // Throw after commit: failed attempts and their audit evidence must survive.
        abort_if($result['status'] !== 200, $result['status'], $result['message'] ?? 'Manager verification failed.');
    }

    public function verify(Request $request, Order $order, string $action): void
    {
        $actor = $request->user();
        if (! $this->required($actor)) return;
        $result = DB::transaction(function () use ($request, $order, $action) {
            $user = User::whereKey($request->user()->id)->lockForUpdate()->firstOrFail();
            abort_unless($this->manager($user), 403, 'A manager must sign in and enter their own PIN.');
            if ($locked = $this->lockStatus($user)) return $locked;
            if (! $this->configured($user)) return ['status' => 409, 'message' => 'Set your manager PIN in Settings before approving this action.'];
            $pin = $request->header('X-Manager-Pin');
            if (! is_string($pin) || $pin === '') return ['status' => 422, 'message' => 'Enter your manager PIN to approve this action.'];
            if (! preg_match('/^[0-9]{6,12}$/D', $pin) || ! Hash::check($this->pepper($user, $pin), $user->manager_pin_hash)) {
                return $this->failure($request, $user, $action);
            }
            if ($user->manager_pin_failures) $user->forceFill(['manager_pin_failures' => 0])->save();
            $request->attributes->set('manager_pin_proof', ['user' => $user->id, 'order' => $order->id,
                'action' => $action, 'hash' => $user->manager_pin_hash]);
            return ['status' => 200];
        });
        abort_if($result['status'] !== 200, $result['status'], $result['message'] ?? 'Manager verification failed.');
    }

    public function assertApproval(Request $request, Order $order, string $action): void
    {
        if (! $this->required($request->user())) return;
        $user = User::whereKey($request->user()->id)->lockForUpdate()->firstOrFail();
        $proof = $request->attributes->get('manager_pin_proof');
        abort_unless($this->manager($user) && is_array($proof) && $proof['user'] === $user->id
            && $proof['order'] === $order->id && $proof['action'] === $action
            && is_string($user->manager_pin_hash) && hash_equals($user->manager_pin_hash, $proof['hash']),
            403, 'Manager approval changed. Enter your PIN again.');
        app(AuditLogService::class)->record($request, 'order.manager_pin_approved', $order, null,
            ['approved_by' => $user->id, 'action' => $action]);
    }
}
