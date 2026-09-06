<?php

namespace App\Models;

use App\Traits\BranchScoped;
use Illuminate\Database\Eloquent\Model;

class RestaurantTable extends Model
{
    use BranchScoped;

    protected $table = 'restaurant_tables';

    protected $fillable = ['branch_id', 'name', 'capacity', 'status', 'position_x', 'position_y'];

    public function orders()
    {
        return $this->hasMany(Order::class, 'table_id');
    }
}
