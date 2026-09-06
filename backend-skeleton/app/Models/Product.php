<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class Product extends Model
{
    use SoftDeletes;

    protected $fillable = ['category_id', 'name', 'sku', 'description', 'base_price', 'is_active'];
    protected $casts = ['base_price' => 'decimal:2', 'is_active' => 'boolean'];

    public function category()
    {
        return $this->belongsTo(Category::class);
    }

    public function images()
    {
        return $this->hasMany(ProductImage::class)->orderBy('sort_order');
    }

    public function variants()
    {
        return $this->hasMany(ProductVariant::class);
    }

    public function modifierGroups()
    {
        return $this->belongsToMany(ModifierGroup::class, 'product_modifier_group');
    }

    public function branches()
    {
        return $this->belongsToMany(Branch::class, 'branch_product')
            ->withPivot(['price_override', 'is_available']);
    }

    public function recipeItems()
    {
        return $this->hasMany(RecipeItem::class);
    }
}
