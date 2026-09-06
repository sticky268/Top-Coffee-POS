<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class OrderItemModifier extends Model
{
    protected $fillable = ['order_item_id', 'modifier_id', 'price_delta'];
    protected $casts = ['price_delta' => 'decimal:2'];

    public function modifier()
    {
        return $this->belongsTo(Modifier::class);
    }
}
