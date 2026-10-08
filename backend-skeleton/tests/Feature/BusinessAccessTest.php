<?php

namespace Tests\Feature;

use App\Models\Branch;
use App\Models\Business;
use App\Models\Order;
use App\Models\User;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Str;
use Tests\TestCase;

class BusinessAccessTest extends TestCase
{
    use RefreshDatabase;

    private function fixtures(): array
    {
        $this->seed(RolePermissionSeeder::class);
        $a = Business::factory()->create();
        $b = Business::factory()->create();
        $own = Branch::factory()->create(['business_id' => $a->id]);
        $foreign = Branch::factory()->create(['business_id' => $b->id]);
        $admin = User::factory()->create(['business_id' => $a->id]);
        $admin->assignRole('admin');
        $admin->branches()->attach($own->id, ['is_primary' => true]);
        return [$admin, $own, $foreign];
    }

    public function test_admin_branch_selection_is_limited_to_own_business(): void
    {
        [$admin, $own, $foreign] = $this->fixtures();
        $this->actingAs($admin);
        foreach (['reports', 'dashboard', 'orders', 'tables', 'ingredients'] as $endpoint) {
            $this->getJson('/api/v1/'.$endpoint.'?branch_id='.$foreign->id)->assertForbidden();
        }
        $this->postJson('/api/v1/orders', ['branch_id' => $foreign->id])->assertForbidden();
        $anotherOwn = Branch::factory()->create(['business_id' => $admin->business_id]);
        $this->getJson('/api/v1/tables?branch_id='.$anotherOwn->id)->assertOk();
    }

    public function test_admin_cannot_read_or_adjust_foreign_orders_when_branch_filter_is_omitted(): void
    {
        [$admin, $own, $foreign] = $this->fixtures();
        $otherUser = User::factory()->create(['business_id' => $foreign->business_id]);
        $otherOrder = Order::create(['uuid' => (string)Str::uuid(), 'branch_id' => $foreign->id,
            'user_id' => $otherUser->id, 'order_type' => 'takeaway', 'status' => 'completed',
            'subtotal' => 10, 'total' => 10]);
        $category = \App\Models\Category::forceCreate(['business_id'=>$foreign->business_id,'name'=>'Foreign fixture','branch_id'=>null]);
        $product = \App\Models\Product::create(['category_id'=>$category->id,'name'=>'Foreign fixture','base_price'=>10]);
        $product->branches()->attach($foreign->id,['is_available'=>true]);
        \App\Models\OrderItem::create(['order_id'=>$otherOrder->id,'product_id'=>$product->id,
            'product_name'=>$product->name,'quantity'=>1,'unit_price'=>10]);
        \App\Models\Payment::create(['order_id'=>$otherOrder->id,'method'=>'cash','amount'=>10,
            'status'=>'completed','processed_by'=>$otherUser->id]);
        $this->actingAs($admin)->getJson('/api/v1/orders')->assertOk()->assertJsonCount(0, 'data');
        $this->getJson('/api/v1/orders/'.$otherOrder->id)->assertNotFound();
        $this->patchJson('/api/v1/orders/'.$otherOrder->id, [
            'items' => [['product_id' => $product->id, 'quantity' => 1]],
        ])->assertForbidden();
        $this->assertDatabaseHas('orders', ['id'=>$otherOrder->id,'total'=>10]);
    }

    public function test_admin_cannot_assign_product_availability_to_a_foreign_business(): void
    {
        [$admin, $own, $foreign] = $this->fixtures();
        $category = \App\Models\Category::forceCreate(['business_id' => $admin->business_id, 'name' => 'Shared category', 'branch_id' => null]);
        $payload = ['name' => 'New product', 'category_id' => $category->id, 'base_price' => 10,
            'branches' => [['branch_id' => $foreign->id, 'is_available' => true]]];
        $this->actingAs($admin)->postJson('/api/v1/products', $payload)->assertForbidden();
        $this->assertDatabaseMissing('products', ['name' => 'New product']);
        $payload['branches'][0]['branch_id'] = $own->id;
        $this->postJson('/api/v1/products', $payload)->assertCreated();
        $product = \App\Models\Product::where('name', 'New product')->firstOrFail();
        $this->patchJson('/api/v1/products/'.$product->id, ['branches' => [
            ['branch_id' => $foreign->id, 'is_available' => true],
        ]])->assertForbidden();
        $this->assertDatabaseMissing('branch_product', ['product_id' => $product->id, 'branch_id' => $foreign->id]);
    }

    public function test_corrupt_cross_business_staff_assignment_is_rejected(): void
    {
        [$admin, $own, $foreign] = $this->fixtures();
        $admin->branches()->attach($foreign->id);
        $this->actingAs($admin)->getJson('/api/v1/auth/me')->assertForbidden();
    }

    public function test_deactivated_account_cannot_reuse_an_existing_token(): void
    {
        [$admin] = $this->fixtures();
        $token = $admin->createToken('before-deactivation')->plainTextToken;
        $this->withToken($token)->getJson('/api/v1/auth/me')->assertOk();
        $admin->update(['is_active' => false]);
        Auth::forgetGuards();
        $this->withToken($token)->getJson('/api/v1/auth/me')->assertUnauthorized();
        Auth::forgetGuards();
        $this->withToken($token)->postJson('/api/v1/orders', [])->assertUnauthorized();
    }
}
