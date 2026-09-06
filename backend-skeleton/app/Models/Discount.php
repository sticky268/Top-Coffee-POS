<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class Discount extends Model
{
    protected $fillable = ['order_id', 'type', 'value', 'amount_applied', 'reason', 'applied_by'];
    protected $casts = ['value' => 'decimal:2', 'amount_applied' => 'decimal:2'];
}
