<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class OrderItem extends Model
{
    protected $fillable = ['order_id', 'product_id', 'product_variant_id', 'quantity', 'unit_price', 'notes', 'product_name', 'variant_name', 'menu_configuration'];
    protected $casts = ['menu_configuration' => 'array', 'unit_price' => 'decimal:2', 'recipe_usage_snapshot' => 'array'];

    public function order()
    {
        return $this->belongsTo(Order::class);
    }

    public function product()
    {
        return $this->belongsTo(Product::class);
    }

    public function variant()
    {
        return $this->belongsTo(ProductVariant::class, 'product_variant_id');
    }

    public function modifiers()
    {
        return $this->hasMany(OrderItemModifier::class);
    }
}
