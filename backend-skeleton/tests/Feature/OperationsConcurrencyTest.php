<?php

namespace Tests\Feature;

use App\Models\{Branch, Business, User, Order, Payment, Ingredient, Unit};
use App\Services\StockMovementService;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Spatie\Permission\Models\Permission;
use Tests\TestCase;

class OperationsConcurrencyTest extends TestCase
{
    private bool $disposable = false;
    private Branch $branch;
    private User $actor;
    private User $other;

    protected function setUp(): void
    {
        parent::setUp();
        if (getenv('RUN_OPERATIONS_RELEASE_CHECKS') !== '1') $this->markTestSkipped('Opt-in disposable MySQL release check.');
        $this->assertTrue(app()->environment('testing'));
        $this->assertSame('mysql', config('database.default'));
        $this->assertSame('operations_testing', config('database.connections.mysql.database'));
        $this->disposable = true;
        $this->artisan('migrate:fresh', ['--force' => true])->assertExitCode(0);
        $business = Business::factory()->create();
        $this->branch = Branch::create(['business_id' => $business->id, 'name' => 'Race cafe', 'code' => 'RACE']);
        $this->actor = User::factory()->create(['business_id' => $business->id]);
        $this->other = User::factory()->create(['business_id' => $business->id]);
        foreach (['orders.create', 'orders.view', 'orders.refund', 'inventory.adjust'] as $permission) {
            Permission::firstOrCreate(['name' => $permission, 'guard_name' => 'web']);
            $this->actor->givePermissionTo($permission);
            $this->other->givePermissionTo($permission);
        }
        foreach ([$this->actor, $this->other] as $user) $user->branches()->attach($this->branch->id);
        $this->actingAs($this->actor);
    }

    protected function tearDown(): void
    {
        if ($this->disposable) $this->artisan('migrate:fresh', ['--force' => true]);
        parent::tearDown();
    }

    private function input(User $user, string $path, array $payload): array
    {
        return ['token' => $user->createToken('disposable-race')->plainTextToken, 'path' => $path,
            'payload' => $payload + ['branch_id' => $this->branch->id, 'uuid' => (string) Str::uuid(), 'expected_user_id' => $user->id]];
    }

    private function open(User $user): int
    {
        return $this->actingAs($user)->postJson('/api/v1/shifts', ['branch_id' => $this->branch->id, 'uuid' => (string) Str::uuid(), 'opening_cash' => 20])->assertCreated()->json('data.id');
    }

    private function sale(): Order
    {
        $this->actingAs($this->actor);
        $order = Order::create(['uuid' => (string) Str::uuid(), 'branch_id' => $this->branch->id, 'user_id' => $this->actor->id, 'order_type' => 'takeaway', 'status' => 'completed', 'subtotal' => 10, 'total' => 10, 'completed_at' => now()]);
        Payment::create(['order_id' => $order->id, 'method' => 'cash', 'amount' => 10, 'status' => 'completed', 'processed_by' => $this->actor->id]);
        return $order;
    }

    /** Both real requests must be blocked on InnoDB locks before release. */
    private function race(array $inputs, string $table, int $id): array
    {
        $dir = sys_get_temp_dir().'/pos-race-'.Str::uuid();
        mkdir($dir, 0700);
        $processes = [];
        DB::beginTransaction();
        try {
            DB::table($table)->where('id', $id)->lockForUpdate()->first();
            foreach ($inputs as $i => $input) {
                file_put_contents("$dir/$i.json", json_encode($input, JSON_THROW_ON_ERROR));
                $process = proc_open([PHP_BINARY, base_path('tests/Support/operation_worker.php'), "$dir/$i.json", "$dir/$i.ready", "$dir/go"],
                    [0 => ['file', '/dev/null', 'r'], 1 => ['file', "$dir/$i.out", 'w'], 2 => ['file', "$dir/$i.err", 'w']], $pipes, base_path());
                $this->assertIsResource($process);
                $processes[$i] = $process;
            }
            $deadline = microtime(true) + 15;
            while (count(glob("$dir/*.ready")) !== count($inputs) && microtime(true) < $deadline) usleep(10000);
            $this->assertCount(count($inputs), glob("$dir/*.ready"), 'Workers must bootstrap before release.');
            touch("$dir/go");
            $deadline = microtime(true) + 10;
            do {
                $waiters = DB::table('performance_schema.data_lock_waits')->count();
                if ($waiters >= count($inputs)) break;
                usleep(20000);
            } while (microtime(true) < $deadline);
            $this->assertGreaterThanOrEqual(count($inputs), $waiters, 'Both requests must overlap while waiting on InnoDB locks.');
            DB::commit();
            $results = [];
            foreach ($processes as $i => $process) {
                $this->assertSame(0, proc_close($process), file_get_contents("$dir/$i.err"));
                unset($processes[$i]);
                $results[] = json_decode(file_get_contents("$dir/$i.out"), true, 512, JSON_THROW_ON_ERROR);
            }
            return $results;
        } finally {
            if (DB::transactionLevel() > 0) DB::rollBack();
            foreach ($processes as $process) { proc_terminate($process); proc_close($process); }
            foreach (glob("$dir/*") as $file) unlink($file);
            rmdir($dir);
        }
    }

    public function test_concurrent_checkouts_allocate_distinct_branch_numbers(): void
    {
        $category = \App\Models\Category::create(['branch_id' => $this->branch->id, 'name' => 'Race coffee']);
        $product = \App\Models\Product::create(['category_id' => $category->id,
            'name' => 'Coffee', 'base_price' => 10, 'is_active' => true]);
        $product->branches()->attach($this->branch->id, ['is_available' => true]);
        $payload = ['order_type' => 'takeaway',
            'items' => [['product_id' => $product->id, 'quantity' => 1]],
            'payment' => ['method' => 'card']];
        $results = $this->race([
            $this->input($this->actor, '/api/v1/orders', $payload),
            $this->input($this->other, '/api/v1/orders', $payload),
        ], 'branches', $this->branch->id);
        $this->assertSame([201, 201], array_column($results, 'status'), json_encode($results));
        $numbers = array_map(fn ($r) => $r['body']['data']['order_number'], $results);
        sort($numbers);
        $this->assertSame([1, 2], $numbers);
        $this->assertDatabaseCount('orders', 2);
        $this->assertDatabaseCount('payments', 2);
    }

    public function test_simultaneous_same_uuid_refund_is_applied_once(): void
    {
        $this->open($this->actor);
        $order = $this->sale();
        $input = $this->input($this->actor, "/api/v1/orders/{$order->id}/refund", ['amount' => 4, 'reason' => 'Race replay', 'inventory_disposition' => 'consumed']);
        $results = $this->race([$input, $input], 'users', $this->actor->id);
        $this->assertSame([200, 200], array_column($results, 'status'), json_encode($results));
        $this->assertDatabaseCount('payment_refunds', 1);
        $this->assertEquals(4, DB::table('payment_refunds')->sum('amount'));
    }

    public function test_two_operators_cannot_over_refund_the_same_sale(): void
    {
        $this->open($this->actor); $this->open($this->other);
        $order = $this->sale();
        $payload = ['amount' => 7, 'reason' => 'Concurrent correction', 'inventory_disposition' => 'consumed'];
        $results = $this->race([$this->input($this->actor, "/api/v1/orders/{$order->id}/refund", $payload), $this->input($this->other, "/api/v1/orders/{$order->id}/refund", $payload)], 'orders', $order->id);
        $statuses = array_column($results, 'status'); sort($statuses);
        $this->assertSame([200, 422], $statuses, json_encode($results));
        $this->assertEquals(7, DB::table('payment_refunds')->sum('amount'));
        $this->assertDatabaseCount('payment_refunds', 1);
    }

    public function test_concurrent_partial_refunds_reconcile_both_committed_amounts(): void
    {
        $this->open($this->actor); $this->open($this->other);
        $order = $this->sale();
        $customer = \App\Models\Customer::create(['branch_id' => $this->branch->id, 'name' => 'Race regular']);
        $order->update(['customer_id' => $customer->id]);
        \App\Models\LoyaltySetting::create(['branch_id' => $this->branch->id, 'is_enabled' => true, 'points_per_currency_unit' => 1]);
        app(\App\Services\LoyaltyService::class)->awardForOrder($order);
        $payload = ['amount' => 4, 'reason' => 'Concurrent partial correction', 'inventory_disposition' => 'consumed'];
        $results = $this->race([$this->input($this->actor, "/api/v1/orders/{$order->id}/refund", $payload), $this->input($this->other, "/api/v1/orders/{$order->id}/refund", $payload)], 'orders', $order->id);
        $this->assertSame([200, 200], array_column($results, 'status'), json_encode($results));
        $totals = array_map(fn ($r) => $r['body']['data']['refunded'], $results); sort($totals);
        $this->assertEquals([4, 8], $totals);
        $this->assertEquals(8, DB::table('payment_refunds')->sum('amount'));
        $this->assertEquals(2, $customer->loyaltyAccount()->firstOrFail()->points_balance);
        $this->assertEquals(8, $order->fresh()->refunded_loyalty_points);
    }

    public function test_closing_shift_racing_a_charge_never_changes_a_closed_drawer(): void
    {
        $shift = $this->open($this->actor); $order = $this->sale();
        $close = $this->input($this->actor, "/api/v1/shifts/$shift/close", ['counted_cash' => 32, 'reason' => 'Concurrent reconciliation']);
        $charge = $this->input($this->actor, "/api/v1/orders/{$order->id}/additional-charge", ['amount' => 2, 'method' => 'cash', 'tendered' => 2, 'reason' => 'Service correction']);
        $results = $this->race([$close, $charge], 'users', $this->actor->id);
        $this->assertSame(200, $results[0]['status'], json_encode($results));
        $this->assertContains($results[1]['status'], [200, 409], json_encode($results));
        $expected = $results[1]['status'] === 200 ? 32 : 30;
        $this->assertDatabaseHas('cashier_shifts', ['id' => $shift, 'status' => 'closed', 'expected_cash' => $expected]);
        $this->assertEquals($expected - 20, Payment::where('shift_id', $shift)->sum('amount'));
        $this->postJson("/api/v1/orders/{$order->id}/additional-charge", ['branch_id' => $this->branch->id, 'uuid' => (string) Str::uuid(), 'amount' => 1, 'method' => 'cash', 'reason' => 'Too late'])->assertConflict();
        $this->assertEquals($expected - 20, Payment::where('shift_id', $shift)->sum('amount'));
    }

    public function test_refund_racing_a_charge_preserves_a_valid_correction_order(): void
    {
        $this->open($this->actor); $this->open($this->other);
        $order = $this->sale();
        $refund = $this->input($this->actor, "/api/v1/orders/{$order->id}/refund", ['amount' => 10, 'reason' => 'Refund race', 'inventory_disposition' => 'consumed']);
        $charge = $this->input($this->other, "/api/v1/orders/{$order->id}/additional-charge", ['amount' => 2, 'method' => 'cash', 'tendered' => 2, 'reason' => 'Charge race']);
        $results = $this->race([$refund, $charge], 'orders', $order->id);
        $this->assertSame(200, $results[0]['status'], json_encode($results));
        $this->assertContains($results[1]['status'], [200, 409], json_encode($results));
        $this->assertEquals(10, DB::table('payment_refunds')->sum('amount'));
        if ($results[1]['status'] === 200) {
            // The charge must precede the refund, never append to a refunded sale.
            $this->assertEquals(12, $results[0]['body']['data']['paid']);
        } else {
            $this->assertEquals(10, Payment::where('order_id', $order->id)->sum('amount'));
        }
    }

    public function test_competing_transfers_cannot_overdraw_source_stock(): void
    {
        $otherBranch = Branch::create(['business_id' => $this->actor->business_id, 'name' => 'Destination', 'code' => 'DEST']);
        foreach ([$this->actor, $this->other] as $user) $user->branches()->attach($otherBranch->id);
        $unit = Unit::create(['name' => 'Kilogram', 'abbreviation' => 'kg', 'conversion_factor' => 1000]);
        $from = Ingredient::create(['branch_id' => $this->branch->id, 'unit_id' => $unit->id, 'name' => 'Beans', 'is_active' => true]);
        $to = Ingredient::create(['branch_id' => $otherBranch->id, 'unit_id' => $unit->id, 'name' => 'Beans', 'is_active' => true]);
        app(StockMovementService::class)->record($from, 'purchase', 1, $this->actor->id, null, null, 10);
        $payload = ['source_ingredient_id' => $from->id, 'destination_ingredient_id' => $to->id, 'quantity' => 0.75, 'reason' => 'Concurrent transfer'];
        $results = $this->race([$this->input($this->actor, '/api/v1/stock/transfer', $payload), $this->input($this->other, '/api/v1/stock/transfer', $payload)], 'ingredients', $from->id);
        $statuses = array_column($results, 'status'); sort($statuses);
        $this->assertSame([200, 422], $statuses, json_encode($results));
        $this->assertEquals(0.25, $from->fresh()->current_stock);
        $this->assertEquals(0.75, $to->fresh()->current_stock);
        $this->assertDatabaseCount('stock_movements', 3);
    }
}
