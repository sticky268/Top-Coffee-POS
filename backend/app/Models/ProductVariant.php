<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class ProductVariant extends Model
{
    protected $fillable = ['product_id', 'name', 'sku', 'price_delta', 'is_active'];
    protected $casts = ['price_delta' => 'decimal:2', 'is_active' => 'boolean'];

    public function product()
    {
        return $this->belongsTo(Product::class);
    }
}
