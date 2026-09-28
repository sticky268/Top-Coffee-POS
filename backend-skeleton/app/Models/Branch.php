<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class Branch extends Model
{
    use HasFactory, SoftDeletes;

    protected $fillable = ['name', 'code', 'address', 'phone', 'timezone', 'is_active'];

    protected $casts = ['is_active' => 'boolean'];

    public function users()
    {
        return $this->belongsToMany(User::class, 'user_branch');
    }

    public function products()
    {
        return $this->belongsToMany(Product::class, 'branch_product')
            ->withPivot(['price_override', 'is_available']);
    }

    public function loyaltyTransactions()
    {
        return $this->hasMany(LoyaltyTransaction::class);
    }
}
