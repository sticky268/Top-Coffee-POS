<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class LoyaltySetting extends Model
{
    protected $fillable = [
        'branch_id',
        'is_enabled',
        'points_per_currency_unit',
        'points_per_reward_currency_unit',
        'minimum_redeem_points',
        'redemption_enabled',
        'expiration_months',
    ];

    protected $casts = [
        'is_enabled' => 'boolean',
        'points_per_currency_unit' => 'decimal:4',
        'points_per_reward_currency_unit' => 'decimal:4',
        'minimum_redeem_points' => 'integer',
        'redemption_enabled' => 'boolean',
        'expiration_months' => 'integer',
    ];

    public function branch()
    {
        return $this->belongsTo(Branch::class);
    }
}