<?php

namespace App\Services;

use Illuminate\Contracts\Cache\LockTimeoutException;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;

class LoginAttempts
{
    private const MAX_FAILURES = 5;
    private const COOLDOWN_SECONDS = 900;

    public function attempt(Request $request, callable $authenticate): JsonResponse
    {
        // The same normalized identity is protected across devices/IPs, including
        // nonexistent accounts. Neither email addresses nor passwords enter cache keys.
        $key = 'login-attempts:v1:'.hash('sha256', strtolower(trim($request->input('email'))));

        try {
            // Serialize check/authenticate/update so simultaneous requests cannot
            // race the fifth failure or clear a newly established lockout.
            return Cache::lock($key.':mutex', 30)->block(5, function () use ($key, $authenticate) {
                $state = Cache::get($key, ['failures' => 0, 'locked_until' => 0]);
                $remaining = $state['locked_until'] - now()->timestamp;
                if ($remaining > 0) return $this->locked($remaining);
                if ($state['locked_until'] > 0) $state = ['failures' => 0, 'locked_until' => 0];

                $response = $authenticate();
                if ($response->getStatusCode() === 200) {
                    Cache::forget($key);
                } elseif ($response->getStatusCode() === 401) {
                    $state['failures']++;
                    if ($state['failures'] >= self::MAX_FAILURES) {
                        $state['locked_until'] = now()->timestamp + self::COOLDOWN_SECONDS;
                    }
                    // Four failures expire after 15 minutes without another failure.
                    // On the fifth, the full cooldown starts from that fifth attempt.
                    Cache::put($key, $state, self::COOLDOWN_SECONDS);
                    if ($state['locked_until'] > 0) return $this->locked(self::COOLDOWN_SECONDS);
                }

                return $response;
            });
        } catch (LockTimeoutException) {
            // Busy authentication must never fall through without protection.
            return response()->json(['success' => false, 'code' => 'LOGIN_BUSY',
                'message' => 'Sign-in is busy. Try again in a few seconds.',
                'retry_after' => 5], 429, ['Retry-After' => '5']);
        }
    }

    private function locked(int $seconds): JsonResponse
    {
        $minutes = (int) ceil($seconds / 60);
        $wait = $minutes === 1 ? '1 minute' : $minutes.' minutes';
        return response()->json(['success' => false, 'code' => 'LOGIN_LOCKED',
            'message' => 'Too many failed sign-in attempts. Try again in '.$wait.'.',
            'retry_after' => $seconds], 429, ['Retry-After' => (string) $seconds]);
    }
}
