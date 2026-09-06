<?php

namespace App\Traits;

use Illuminate\Database\Eloquent\Builder;

/**
 * Applies automatic branch filtering to a model's queries based on the
 * authenticated user's assigned branches — unless they hold the
 * 'branches.view-all' permission (Admins).
 *
 * Models using this trait MUST have a `branch_id` column.
 */
trait BranchScoped
{
    protected static function bootBranchScoped(): void
    {
        static::addGlobalScope('branch', function (Builder $builder) {
            $user = auth()->user();

            if (! $user) {
                return; // console/seeders/unauthenticated context — no scoping
            }

            if ($user->can('branches.view-all')) {
                return;
            }

            $builder->whereIn('branch_id', $user->branches()->pluck('branches.id'));
        });
    }
}
