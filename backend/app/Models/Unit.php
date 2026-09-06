<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class Unit extends Model
{
    protected $fillable = ['name', 'abbreviation', 'base_unit_id', 'conversion_factor'];
    protected $casts = ['conversion_factor' => 'decimal:6'];
}
