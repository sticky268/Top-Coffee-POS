<?php

namespace App\Http\Controllers\Api\V1\Auth;

use App\Http\Controllers\Controller;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\DB;
use App\Services\SessionSecurity;
use Illuminate\Support\Facades\Validator;

class AuthController extends Controller
{
    public function login(Request $request)
    {
        $validator = Validator::make($request->all(), [
            'email' => 'required|email|max:255',
            'password' => 'required|string|max:4096',
            'device_id' => 'nullable|uuid',
            'device_name' => 'required|string|max:255', // for token identification/revocation
        ]);

        if ($validator->fails()) {
            return response()->json([
                'success' => false,
                'message' => 'Validation failed',
                'errors' => $validator->errors(),
            ], 422);
        }

        $user = User::where('email', $request->email)->first();

        // Equal-cost hashing also runs for nonexistent accounts.
        $valid = Hash::check($request->password, $user?->password
            ?? '$2y$12$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2uheWG/igi.');
        if (! $user || ! $valid) {
            app(SessionSecurity::class)->audit($request, 'auth.login_failed', $user);
            return response()->json([
                'success' => false,
                'message' => 'Invalid credentials',
            ], 401);
        }

        if (! $user->is_active) {
            return response()->json([
                'success' => false,
                'message' => 'Account is deactivated',
            ], 403);
        }

        if (! $user->business || ! $user->business->is_active
            || $user->branches()->where('business_id', '!=', $user->business_id)->exists()) {
            return response()->json(['success' => false, 'message' => 'Your business or branch assignments require administrator review.'], 403);
        }
        $token = DB::transaction(function () use ($request, $user) {
            User::whereKey($user->id)->lockForUpdate()->firstOrFail();
            $name = $request->filled('device_id')
                ? 'device:'.$request->input('device_id') : $request->input('device_name');
            if ($request->filled('device_id')) $user->tokens()->where('name', $name)->delete();
            $issued = $user->createToken($name, ['*'], now()->addMinutes(
                min(720, max(1, (int) (config('sanctum.expiration') ?: 720)))
            ));
            app(SessionSecurity::class)->audit($request, 'auth.login_succeeded', $user,
                ['session_id' => $issued->accessToken->id]);
            return ['token' => $issued->plainTextToken, 'expires_at' => $issued->accessToken->expires_at->toIso8601String()];
        });

        return response()->json([
            'success' => true,
            'data' => [
                'token' => $token['token'],
                'user' => [
                    'id' => $user->id,
                    'name' => $user->name,
                    'email' => $user->email,
                    'roles' => $user->getRoleNames(),
                    'permissions' => $user->getAllPermissions()->pluck('name'),
                    'session_expires_at' => $token['expires_at'],
                    'allowed_payment_methods' => config('payments.allowed_methods'),
                    'checkout_controls' => $user->business->only(['require_cash_shift', 'require_manager_controls', 'manager_discount_percent']),
                    'branches' => $user->branches()->select('branches.id', 'branches.name', 'branches.code')->get(),
                ],
            ],
        ]);
    }

    public function logout(Request $request)
    {
        DB::transaction(function () use ($request) {
            app(SessionSecurity::class)->audit($request, 'auth.logged_out', $request->user());
            $request->user()->currentAccessToken()?->delete();
        });

        return response()->json(['success' => true, 'message' => 'Logged out']);
    }

    public function sessions(Request $request)
    {
        return ['success' => true, 'data' => $request->user()->tokens()
            ->latest()->limit(100)->get(['id', 'name', 'created_at', 'last_used_at', 'expires_at'])
            ->map(fn ($token) => $token->only(['id', 'name', 'created_at', 'last_used_at', 'expires_at'])
                + ['current' => $token->id === $request->user()->currentAccessToken()?->id])];
    }

    public function revokeSession(Request $request, int $session)
    {
        DB::transaction(function () use ($request, $session) {
            $token = $request->user()->tokens()->whereKey($session)->lockForUpdate()->firstOrFail();
            app(SessionSecurity::class)->audit($request, 'auth.session_revoked', $request->user(),
                ['session_id' => $token->id]);
            $token->delete();
        });
        return ['success' => true];
    }

    public function logoutAll(Request $request)
    {
        DB::transaction(function () use ($request) {
            User::whereKey($request->user()->id)->lockForUpdate()->firstOrFail();
            app(SessionSecurity::class)->audit($request, 'auth.all_sessions_revoked', $request->user());
            $request->user()->tokens()->delete();
        });
        return ['success' => true];
    }

    public function me(Request $request)
    {
        $user = $request->user();
        $accessToken = $user->currentAccessToken();

        return response()->json([
            'success' => true,
            'data' => [
                'id' => $user->id,
                'name' => $user->name,
                'email' => $user->email,
                'roles' => $user->getRoleNames(),
                'permissions' => $user->getAllPermissions()->pluck('name'),
                'session_expires_at' => $accessToken instanceof \Laravel\Sanctum\PersonalAccessToken
                    ? $accessToken->expires_at?->toIso8601String() : null,
                    'allowed_payment_methods' => config('payments.allowed_methods'),
                    'checkout_controls' => $user->business->only(['require_cash_shift', 'require_manager_controls', 'manager_discount_percent']),
                'branches' => $user->branches()->select('branches.id', 'branches.name', 'branches.code')->get(),
            ],
        ]);
    }
}
