<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class ExpenseCategory extends Model
{
    use \App\Traits\BusinessOwned;

    protected $fillable = ['name'];
}
