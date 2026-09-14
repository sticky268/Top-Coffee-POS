<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class RecipeItem extends Model
{
    protected $fillable = [
        'branch_id',
        'product_id',
        'modifier_id',
        'ingredient_id',
        'quantity_used',
    ];

    protected $casts = [
        'quantity_used' => 'decimal:3',
    ];

    public function branch()
    {
        return $this->belongsTo(Branch::class);
    }

    public function ingredient()
    {
        return $this->belongsTo(Ingredient::class);
    }

    public function product()
    {
        return $this->belongsTo(Product::class);
    }

    public function modifier()
    {
        return $this->belongsTo(Modifier::class);
    }
}