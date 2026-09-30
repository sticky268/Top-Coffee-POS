<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class Business extends Model
{
    use HasFactory, SoftDeletes;

    protected $fillable = [
        'name',
        'slug',
        'email',
        'phone',
        'address',
        'is_active',
        'plan_id',
        'status',
        'started_at',
        'expires_at',
    ];

    protected $casts = [
        'is_active' => 'boolean',
        'started_at' => 'datetime',
        'expires_at' => 'datetime',
    ];

    public function plan()
    {
        return $this->belongsTo(Plan::class);
    }

    public function branches()
    {
        return $this->hasMany(Branch::class);
    }

    /**
     * Get the effective subscription status.
     */
    public function subscriptionStatus(): string
    {
        if ($this->status === 'suspended') {
            return 'suspended';
        }

        if ($this->expires_at !== null && $this->expires_at->isPast()) {
            return 'expired';
        }

        if ($this->status === 'active') {
            return 'active';
        }

        return 'trial';
    }

    /**
     * Determine whether the subscription allows normal operation.
     */
    public function subscriptionIsActive(): bool
    {
        return in_array($this->subscriptionStatus(), ['trial', 'active'], true);
    }

    /**
     * Determine whether the subscription has expired.
     */
    public function subscriptionIsExpired(): bool
    {
        return $this->subscriptionStatus() === 'expired';
    }

    /**
     * Determine whether the business can modify its data.
     */
    public function canModifyData(): bool
    {
        return $this->is_active
            && $this->subscriptionIsActive();
    }
}
