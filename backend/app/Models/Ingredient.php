<?php

namespace App\Models;

use App\Traits\BranchScoped;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class Ingredient extends Model
{
    use BranchScoped, SoftDeletes;

    // current_stock is intentionally NOT fillable — it must only ever be
    // changed by StockMovementService, alongside a stock_movements row,
    // inside a DB transaction. See StockMovementService::record().
    protected $fillable = ['branch_id', 'unit_id', 'name', 'reorder_threshold', 'is_active'];

    protected $casts = [
        'current_stock' => 'decimal:3',
        'reorder_threshold' => 'decimal:3',
        'is_active' => 'boolean',
    ];

    public function unit()
    {
        return $this->belongsTo(Unit::class);
    }

    public function movements()
    {
        return $this->hasMany(StockMovement::class);
    }

    public function isLowStock(): bool
    {
        return $this->current_stock <= $this->reorder_threshold;
    }
}
