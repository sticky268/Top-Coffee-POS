<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class LoyaltyTransaction extends Model
{
    protected $fillable = [
        'customer_loyalty_account_id',
        'customer_id',
        'branch_id',
        'order_id',
        'type',
        'points',
        'balance_after',
        'description',
    ];

    protected $casts = [
        'points' => 'integer',
        'balance_after' => 'integer',
    ];

    public function account()
    {
        return $this->belongsTo(
            CustomerLoyaltyAccount::class,
            'customer_loyalty_account_id'
        );
    }

    public function customer()
    {
        return $this->belongsTo(Customer::class);
    }

    public function branch()
    {
        return $this->belongsTo(Branch::class);
    }

    public function order()
    {
        return $this->belongsTo(Order::class);
    }
}
