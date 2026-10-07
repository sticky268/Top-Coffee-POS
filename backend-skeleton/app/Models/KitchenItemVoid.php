<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class KitchenItemVoid extends Model
{
    protected $fillable = [
        'order_id',
        'order_number',
        'order_item_id',
        'kitchen_ticket_id',
        'quantity',
        'reason',
        'kitchen_status',
        'voided_by',
    ];

    public function order()
    {
        return $this->belongsTo(Order::class);
    }

    public function orderItem()
    {
        return $this->belongsTo(OrderItem::class);
    }

    public function kitchenTicket()
    {
        return $this->belongsTo(KitchenTicket::class);
    }

    public function voidedBy()
    {
        return $this->belongsTo(User::class, 'voided_by');
    }
}
