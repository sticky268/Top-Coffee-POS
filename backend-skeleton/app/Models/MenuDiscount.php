<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class MenuDiscount extends Model
{
    use \App\Traits\BusinessOwned;

    protected $guarded = ['id', 'business_id'];
    protected $casts = ['is_active' => 'boolean', 'requires_manager' => 'boolean', 'value' => 'decimal:2'];
}
