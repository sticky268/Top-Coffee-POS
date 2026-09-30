<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class Plan extends Model
{
    use HasFactory;

    protected $fillable = [
        'name',
        'slug',
        'branch_limit',
        'price',
        'billing_interval',
        'is_active',
    ];

    protected $casts = [
        'branch_limit' => 'integer',
        'price' => 'decimal:2',
        'is_active' => 'boolean',
    ];

    public function businesses()
    {
        return $this->hasMany(Business::class);
    }
}
