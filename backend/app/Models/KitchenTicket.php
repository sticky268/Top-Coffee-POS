<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class KitchenTicket extends Model
{
    protected $fillable = ['order_id', 'status', 'sent_at', 'ready_at', 'completed_at'];
    protected $casts = ['sent_at' => 'datetime', 'ready_at' => 'datetime', 'completed_at' => 'datetime'];

    public function order()
    {
        return $this->belongsTo(Order::class);
    }
}
