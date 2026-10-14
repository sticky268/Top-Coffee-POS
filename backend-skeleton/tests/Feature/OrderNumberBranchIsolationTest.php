<?php

namespace Tests\Feature;

use App\Models\Branch;
use App\Models\Business;
use App\Models\Order;
use App\Models\User;
use App\Services\OrderNumberService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

class OrderNumberBranchIsolationTest extends TestCase
{
    use RefreshDatabase;

    public function test_order_numbers_increment_independently_per_branch(): void
    {
        $business = Business::factory()->create();
        $branchA = Branch::create([
            'business_id' => $business->id,
            'name' => 'Branch A',
            'code' => 'ONA',
        ]);
        $branchB = Branch::create([
            'business_id' => $business->id,
            'name' => 'Branch B',
            'code' => 'ONB',
        ]);
        $user = User::factory()->create();

        $this->createOrder($branchA->id, $user->id, 1);
        $this->createOrder($branchA->id, $user->id, 2);
        $this->createOrder($branchB->id, $user->id, 1);

        $service = app(OrderNumberService::class);

        $nextA = DB::transaction(fn () => $service->nextForBranch($branchA->id));
        $nextB = DB::transaction(fn () => $service->nextForBranch($branchB->id));

        $this->assertSame(3, $nextA);
        $this->assertSame(2, $nextB);
    }

    public function test_same_order_number_is_allowed_across_branches_but_not_within_one_branch(): void
    {
        $business = Business::factory()->create();
        $branchA = Branch::create([
            'business_id' => $business->id,
            'name' => 'Branch A',
            'code' => 'OUA',
        ]);
        $branchB = Branch::create([
            'business_id' => $business->id,
            'name' => 'Branch B',
            'code' => 'OUB',
        ]);
        $user = User::factory()->create();

        $this->createOrder($branchA->id, $user->id, 1);
        $this->createOrder($branchB->id, $user->id, 1);

        $this->expectException(\Illuminate\Database\QueryException::class);
        $this->createOrder($branchA->id, $user->id, 1);
    }

    private function createOrder(int $branchId, int $userId, int $orderNumber): Order
    {
        return Order::withoutGlobalScopes()->create([
            'uuid' => (string) \Illuminate\Support\Str::uuid(),
            'branch_id' => $branchId,
            'order_number' => $orderNumber,
            'user_id' => $userId,
            'order_type' => 'takeaway',
            'status' => 'completed',
            'subtotal' => 1,
            'discount_total' => 0,
            'tax_total' => 0,
            'total' => 1,
            'completed_at' => now(),
        ]);
    }
}
