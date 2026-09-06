<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class PaymentRefund extends Model
{
    protected $fillable = ['payment_id', 'amount', 'reason', 'processed_by'];
    protected $casts = ['amount' => 'decimal:2'];
}
