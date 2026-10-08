<?php

namespace App\Traits;

use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Facades\DB;

trait BusinessOwned
{
    protected static function bootBusinessOwned(): void
    {
        static::addGlobalScope('business_owner', function (Builder $query) {
            if ($user = auth()->user()) {
                $query->where($query->getModel()->qualifyColumn('business_id'), $user->business_id);
            }
        });

        static::creating(function ($model) {
            if ($model->business_id !== null) return;
            // API controllers do not accept business_id from the client.
            $owner = auth()->user()?->business_id;
            if ($owner === null && $model->branch_id !== null) {
                $owner = DB::table('branches')->where('id', $model->branch_id)->value('business_id');
            }
            if ($owner === null && $model->category_id !== null) {
                $owner = DB::table('categories')->where('id', $model->category_id)->value('business_id');
            }
            if ($owner === null && $model instanceof \App\Models\AuditLog && $model->user_id !== null) {
                $owner = DB::table('users')->where('id', $model->user_id)->value('business_id');
            }
            // Legacy single-business seeders remain usable. Multi-business
            // console imports must set ownership explicitly; unknown rows stay hidden.
            if ($owner === null) {
                $businesses = DB::table('businesses')->limit(2)->pluck('id');
                if ($businesses->count() === 1) $owner = $businesses->first();
            }
            $model->business_id = $owner;
        });
    }
}
