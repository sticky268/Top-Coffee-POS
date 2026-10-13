<?php

namespace App\Services;

use App\Models\Branch;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class OperationService
{
    public function branch(Request $request, string $permission): int
    {
        abort_unless($request->user()->can($permission), 403, 'Permission required: '.$permission);
        $request->validate(['branch_id' => 'required|integer|min:1']);
        $branch = Branch::whereKey($request->integer('branch_id'))->where('business_id', $request->user()->business_id)->firstOrFail();
        abort_unless($request->user()->can('branches.view-all') || $request->user()->branches()->where('branches.id', $branch->id)->exists(), 403, 'Branch access denied.');
        return $branch->id;
    }

    // Lock the actor first: repeated requests cannot perform the operation twice.
    // Store the response in the same transaction as the financial/stock change.
    public function run(Request $request, int $branch, string $operation, callable $callback): array
    {
        $request->validate(['uuid' => 'required|uuid', 'expected_user_id' => 'nullable|integer']);
        abort_if($request->filled('expected_user_id') && $request->integer('expected_user_id') !== $request->user()->id, 403, 'The original operator must confirm this request.');
        return DB::transaction(function () use ($request, $branch, $operation, $callback) {
            User::whereKey($request->user()->id)->lockForUpdate()->firstOrFail();
            $input = $request->except('uuid');
            ksort($input);
            $hash = hash('sha256', json_encode($input));
            $key = ['user_id' => $request->user()->id, 'uuid' => $request->input('uuid')];
            $previous = DB::table('operation_requests')->where($key)->first();
            if ($previous) {
                abort_unless($previous->operation === $operation && (int) $previous->branch_id === $branch && $previous->fingerprint === $hash, 409, 'This request reference was used with different details.');
                return json_decode($previous->result, true);
            }
            $result = $callback();
            DB::table('operation_requests')->insert($key + ['branch_id' => $branch, 'operation' => $operation, 'fingerprint' => $hash, 'result' => json_encode($result), 'created_at' => now(), 'updated_at' => now()]);
            return $result;
        }, 3);
    }

    public static function cents(mixed $value): int
    {
        return (int) round((float) $value * 100);
    }
}
