<?php

namespace App\Models;

use App\Traits\BranchScoped;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\SoftDeletes;

class Order extends Model
{
    use BranchScoped, SoftDeletes;

    protected $fillable = [
        'uuid', 'request_fingerprint', 'branch_id', 'order_number', 'user_id', 'customer_id', 'table_id', 'order_type',
        'status', 'subtotal', 'discount_total', 'tax_total', 'total',
        'held_at', 'completed_at', 'sync_status', 'created_offline_at',
    ];

    protected $casts = [
        'order_number' => 'integer',
        'subtotal' => 'decimal:2',
        'discount_total' => 'decimal:2',
        'tax_total' => 'decimal:2',
        'total' => 'decimal:2',
        'held_at' => 'datetime',
        'completed_at' => 'datetime',
        'created_offline_at' => 'datetime',
    ];

    protected static function booted(): void
    {
        static::saving(function (Order $order) {
            if ($order->isDirty(['discount_total', 'subtotal'])) {
                // Audit only after a persisted ID exists, in the same transaction.
                $discount = \App\Services\OperationService::cents($order->discount_total);
                $subtotal = \App\Services\OperationService::cents($order->subtotal);
                abort_if($discount > $subtotal, 422, 'Discount cannot exceed the subtotal.');
                $actor = auth()->user();
                if ($actor && $actor->business->require_manager_controls) {
                    abort_if($discount > 0 && $discount * 100 > $subtotal * (float) $actor->business->manager_discount_percent
                        && ! app(\App\Services\CheckoutControls::class)->manager($actor), 403, 'A manager must sign in to approve this discount.');
                }
            }
        });
        static::saved(function (Order $order) {
            if ($order->wasRecentlyCreated || $order->wasChanged(['discount_total', 'subtotal'])) {
                app(\App\Services\CheckoutControls::class)->discount($order);
            }
        });
    }

    /** Indexed completion-time interval, with a fallback for legacy sales. */
    public function scopeCompletedDuring(Builder $query, $from, $until): Builder
    {
        return $query->where(function ($query) use ($from, $until) {
            $query->where(fn ($query) => $query->where('orders.completed_at', '>=', $from)
                ->where('orders.completed_at', '<', $until))
                ->orWhere(fn ($query) => $query->whereNull('orders.completed_at')
                    ->where('orders.created_at', '>=', $from)->where('orders.created_at', '<', $until));
        });
    }

    public function items()
    {
        return $this->hasMany(OrderItem::class);
    }

    public function payments()
    {
        return $this->hasMany(Payment::class);
    }

    public function discounts()
    {
        return $this->hasMany(Discount::class);
    }

    public function branch()
    {
        return $this->belongsTo(Branch::class, 'branch_id');
    }
    
    public function customer()
    {
        return $this->belongsTo(Customer::class);
    }

    public function table()
    {
        return $this->belongsTo(RestaurantTable::class, 'table_id');
    }

    public function cashier()
    {
        return $this->belongsTo(User::class, 'user_id');
    }

    public function loyaltyTransactions()
    {
        return $this->hasMany(LoyaltyTransaction::class);
    }
}
