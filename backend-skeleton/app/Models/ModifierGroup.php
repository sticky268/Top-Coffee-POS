<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class ModifierGroup extends Model
{
    use \App\Traits\BusinessOwned;

    protected $fillable = ['name', 'min_select', 'max_select', 'is_required'];
    protected $casts = ['is_required' => 'boolean'];

    public function modifiers()
    {
        return $this->hasMany(Modifier::class);
    }

    public function products()
    {
        return $this->belongsToMany(Product::class, 'product_modifier_group');
    }
}
