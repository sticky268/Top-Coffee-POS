<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class KitchenTicket extends Model
{
    protected $fillable = ['order_id', 'status', 'sent_at', 'ready_at', 'completed_at', 'cancellation_acknowledged_at'];
    protected $casts = ['sent_at' => 'datetime', 'ready_at' => 'datetime', 'completed_at' => 'datetime', 'cancellation_acknowledged_at' => 'datetime'];

    public function items()
    {
        return $this->belongsToMany(OrderItem::class, 'kitchen_ticket_items')
            ->withPivot('quantity')
            ->withTimestamps();
    }

    public function order()
    {
        return $this->belongsTo(Order::class);
    }
}
