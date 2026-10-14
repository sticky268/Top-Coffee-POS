<?php

namespace Tests\Feature;

use App\Models\{Branch, Business, Category, Ingredient, Product, Supplier, Unit, User};
use App\Services\StockMovementService;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\{Artisan, DB};
use Tests\TestCase;

class SystemIntegrityReviewTest extends TestCase
{
    use RefreshDatabase;
    private Branch $branch;
    private User $actor;
    private Ingredient $ingredient;
    private Product $product;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
        $business = Business::factory()->create();
        $this->branch = Branch::factory()->create(['business_id' => $business->id]);
        $this->actor = User::factory()->create(['business_id' => $business->id]);
        $this->actor->assignRole('admin');
        $this->actor->branches()->attach($this->branch->id);
        $this->actingAs($this->actor);
        $unit = Unit::create(['name' => 'Gram', 'abbreviation' => 'g', 'conversion_factor' => 1]);
        $this->ingredient = Ingredient::create(['branch_id' => $this->branch->id,
            'unit_id' => $unit->id, 'name' => 'Beans', 'is_active' => true]);
        $category = Category::create(['branch_id' => $this->branch->id, 'name' => 'Coffee']);
        $this->product = Product::create(['category_id' => $category->id, 'name' => 'Coffee', 'base_price' => 10]);
    }

    public function test_unrepresentable_stock_and_recipe_quantities_are_rejected_without_writes(): void
    {
        $this->postJson('/api/v1/ingredients/'.$this->ingredient->id.'/movements',
            ['type' => 'purchase', 'quantity' => 0.0004])->assertUnprocessable();
        $this->putJson('/api/v1/products/'.$this->product->id.'/recipe',
            ['branch_id' => $this->branch->id, 'items' => [
                ['ingredient_id' => $this->ingredient->id, 'quantity_used' => 0.0004],
            ]])->assertUnprocessable();
        $supplier = Supplier::create(['branch_id' => $this->branch->id, 'name' => 'Supplier']);
        $this->postJson('/api/v1/purchases', ['branch_id' => $this->branch->id,
            'supplier_id' => $supplier->id, 'purchased_at' => '2026-10-14',
            'items' => [['ingredient_id' => $this->ingredient->id, 'quantity' => 0.0004, 'unit_cost' => 100]],
        ])->assertUnprocessable();
        $this->assertDatabaseCount('stock_movements', 0);
        $this->assertDatabaseCount('purchases', 0);
        $this->assertDatabaseCount('recipe_items', 0);
    }

    public function test_stock_cache_equals_ledger_and_readiness_detects_drift_without_repairing_data(): void
    {
        $service = app(StockMovementService::class);
        $service->record($this->ingredient, 'purchase', 0.1, $this->actor->id);
        $service->record($this->ingredient, 'purchase', 0.2, $this->actor->id);
        $service->record($this->ingredient, 'wastage', -0.3, $this->actor->id, 'Spilled');
        $this->assertEquals(0, $this->ingredient->fresh()->current_stock);
        $this->assertEquals(0, DB::table('stock_movements')->sum('quantity'));
        // Corruption simulation only; real changes always use the service.
        DB::table('ingredients')->where('id', $this->ingredient->id)->update(['current_stock' => 1]);
        Artisan::call('pos:production-check', ['--json' => true]);
        $report = json_decode(Artisan::output(), true, flags: JSON_THROW_ON_ERROR);
        $this->assertFalse($report['checks']['stock_cache_matches_ledger']);
        $this->assertEquals(1, $this->ingredient->fresh()->current_stock);
    }

    public function test_invalid_branch_timezone_is_rejected(): void
    {
        $this->patchJson('/api/v1/branches/'.$this->branch->id,
            ['timezone' => 'Not/A_Timezone'])->assertUnprocessable();
    }
}
