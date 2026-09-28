<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class CustomerLoyaltyAccount extends Model
{
    protected $fillable = [
        'customer_id',
        'points_balance',
        'lifetime_earned',
        'lifetime_redeemed',
    ];

    protected $casts = [
        'points_balance' => 'integer',
        'lifetime_earned' => 'integer',
        'lifetime_redeemed' => 'integer',
    ];

    public function customer()
    {
        return $this->belongsTo(Customer::class);
    }

    public function transactions()
    {
        return $this->hasMany(LoyaltyTransaction::class);
    }
}
