<?php

namespace App\Models;

use App\Traits\BranchScoped;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class Expense extends Model
{
    use BranchScoped, SoftDeletes;

    protected $fillable = [
        'branch_id', 'expense_category_id', 'user_id', 'amount',
        'description', 'spent_at', 'attachment_path',
    ];

    protected $casts = ['amount' => 'decimal:2', 'spent_at' => 'date'];
}
