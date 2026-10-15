<?php

namespace App\Http\Controllers\Api\V1\Auth;

use App\Models\User;
use App\Services\ManagerPin;
use Illuminate\Http\Request;

class ManagerPinController
{
    public function show(Request $request, ManagerPin $pins)
    {
        $user = User::findOrFail($request->user()->id);
        abort_unless($pins->manager($user), 403, 'A manager must sign in.');
        return response()->json(['data' => ['user_id' => $user->id, 'configured' => $pins->configured($user),
            'locked' => $user->manager_pin_locked_until?->isFuture() ?? false]])->header('Cache-Control', 'no-store');
    }

    public function store(Request $request, ManagerPin $pins)
    {
        abort_unless($pins->manager(User::findOrFail($request->user()->id)), 403, 'A manager must sign in.');
        $pins->enroll($request);
        return response()->json(['data' => ['configured' => true]])->header('Cache-Control', 'no-store');
    }
}
