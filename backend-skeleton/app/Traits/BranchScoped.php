<?php

namespace App\Traits;

use Illuminate\Database\Eloquent\Builder;

/**
 * Restricts authenticated queries to the user's business and assigned branches.
 * 'branches.view-all' bypasses assignments but retains business isolation.
 *
 * Models using this trait MUST have a `branch_id` column.
 */
trait BranchScoped
{
    protected static function bootBranchScoped(): void
    {
        // An admin may view all branches of their business, not other tenants.
        // Keep this separate from the assignment scope so adjustment workflows
        // that remove only the 'branch' scope still retain tenant isolation.
        static::addGlobalScope('business', function (Builder $builder) {
            $user = auth()->user();
            if (! $user) return;
            $builder->whereIn($builder->getModel()->qualifyColumn('branch_id'),
                \Illuminate\Support\Facades\DB::table('branches')->select('id')
                    ->where('business_id', $user->business_id));
        });
        static::addGlobalScope('branch', function (Builder $builder) {
            $user = auth()->user();

            if (! $user) {
                return; // console/seeders/unauthenticated context — no scoping
            }

            if ($user->can('branches.view-all')) {
                return;
            }

            $builder->whereIn($builder->getModel()->qualifyColumn('branch_id'), $user->branches()->pluck('branches.id'));
        });
    }
}
