<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class Payment extends Model
{
    protected $fillable = [
        'order_id', 'method', 'amount', 'tendered', 'change_due',
        'status', 'reference', 'processed_by', 'shift_id', 'verification',
    ];

    protected $casts = [
        'amount' => 'decimal:2',
        'tendered' => 'decimal:2',
        'change_due' => 'decimal:2',
    ];

    protected static function booted(): void
    {
        static::creating(function (Payment $payment) {
            if ($payment->shift_id !== null || ! auth()->check()) return;
            $order = $payment->order;
            if ($order) $payment->shift_id = app(\App\Services\ShiftService::class)->paymentShift($order->branch_id, $payment->processed_by);
        });
    }

    public function order()
    {
        return $this->belongsTo(Order::class);
    }

    public function refunds()
    {
        return $this->hasMany(PaymentRefund::class);
    }
}
