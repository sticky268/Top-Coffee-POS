<?php

namespace App\Models;

use App\Traits\BranchScoped;
use Illuminate\Database\Eloquent\Model;

class Purchase extends Model
{
    use BranchScoped;

    protected $fillable = ['branch_id', 'supplier_id', 'created_by', 'total_cost', 'purchased_at'];
    protected $casts = ['total_cost' => 'decimal:2', 'purchased_at' => 'date'];

    public function items()
    {
        return $this->hasMany(PurchaseItem::class);
    }

    public function supplier()
    {
        return $this->belongsTo(Supplier::class);
    }
}
