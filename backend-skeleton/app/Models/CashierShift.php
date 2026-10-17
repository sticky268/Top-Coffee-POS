<?php

namespace App\Models;

use App\Traits\BranchScoped;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class CashierShift extends Model
{
    use BranchScoped;
    protected $guarded = ['id'];

    public function cashier(): BelongsTo
    {
        return $this->belongsTo(User::class, 'user_id')->select(['id', 'name']);
    }

    protected $casts = ['opening_cash' => 'decimal:2', 'expected_cash' => 'decimal:2', 'counted_cash' => 'decimal:2', 'difference' => 'decimal:2', 'closed_at' => 'datetime', 'reviewed_at' => 'datetime'];
}
