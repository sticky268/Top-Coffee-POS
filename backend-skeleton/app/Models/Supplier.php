<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class Supplier extends Model
{
    use \App\Traits\BusinessOwned;

    use SoftDeletes;

    protected $fillable = ['branch_id', 'name', 'contact_name', 'phone', 'email'];
}
