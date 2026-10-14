<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class Customer extends Model
{
    use \App\Traits\BusinessOwned;

    use SoftDeletes;

    protected $fillable = ['branch_id', 'name', 'phone', 'email', 'notes'];

    public function orders()
    {
        return $this->hasMany(Order::class);
    }

    public function loyaltyAccount()
    {
        return $this->hasOne(CustomerLoyaltyAccount::class);
    }

    public function loyaltyTransactions()
    {
        return $this->hasMany(LoyaltyTransaction::class);
    }
}
