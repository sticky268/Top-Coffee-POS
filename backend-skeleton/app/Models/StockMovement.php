<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class StockMovement extends Model
{
    // Append-only ledger. No fillable 'balance_after' manipulation outside
    // StockMovementService — this model is intentionally "dumb".
    protected $fillable = [
        'ingredient_id', 'branch_id', 'type', 'quantity', 'balance_after',
        'reference_type', 'reference_id', 'reason', 'created_by',
    ];

    protected $casts = [
        'quantity' => 'decimal:3',
        'balance_after' => 'decimal:3',
    ];

    public function ingredient()
    {
        return $this->belongsTo(Ingredient::class);
    }

    public function reference()
    {
        return $this->morphTo();
    }
}
