<?php

namespace Tests\Feature;

use App\Models\Branch;
use App\Models\Business;
use App\Models\Category;
use App\Models\Ingredient;
use App\Models\Modifier;
use App\Models\ModifierGroup;
use App\Models\Product;
use App\Models\RecipeItem;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Spatie\Permission\Models\Permission;
use Tests\TestCase;

class IngredientImpactTest extends TestCase
{
    use RefreshDatabase;

    private Business $business;
    private Branch $branch;
    private User $user;
    private Ingredient $ingredient;

    protected function setUp(): void
    {
        parent::setUp();
        $this->business = Business::factory()->create();
        $this->branch = Branch::factory()->create(['business_id' => $this->business->id]);
        $this->user = User::factory()->create(['business_id' => $this->business->id]);
        $this->user->branches()->attach($this->branch->id, ['is_primary' => true]);
        foreach (['inventory.view', 'branches.view-all'] as $permission) {
            Permission::firstOrCreate(['name' => $permission, 'guard_name' => 'web']);
        }
        $this->user->givePermissionTo('inventory.view');
        $unit = DB::table('units')->insertGetId([
            'name' => 'Gram', 'abbreviation' => 'g', 'conversion_factor' => 1,
            'created_at' => now(), 'updated_at' => now(),
        ]);
        $this->ingredient = Ingredient::create([
            'branch_id' => $this->branch->id, 'unit_id' => $unit,
            'name' => 'Milk', 'reorder_threshold' => 5, 'is_active' => true,
        ]);
    }

    private function product(string $name, bool $active = true, bool $available = true): Product
    {
        $category = Category::forceCreate([
            'business_id' => $this->business->id, 'name' => 'Coffee',
            'is_active' => true, 'sort_order' => 1,
        ]);
        $product = Product::forceCreate([
            'business_id' => $this->business->id, 'category_id' => $category->id,
            'name' => $name, 'base_price' => 2, 'is_active' => $active,
        ]);
        $product->branches()->attach($this->branch->id, ['is_available' => $available]);
        return $product;
    }

    private function recipe(Product $product, ?int $branch = null): void
    {
        RecipeItem::create([
            'branch_id' => $branch ?? $this->branch->id,
            'product_id' => $product->id, 'modifier_id' => null,
            'ingredient_id' => $this->ingredient->id, 'quantity_used' => 1,
        ]);
    }

    private function url(string $query = ''): string
    {
        return "/api/v1/ingredients/{$this->ingredient->id}/products?branch_id={$this->branch->id}{$query}";
    }

    public function test_links_include_base_and_optional_modifier_recipes_once_and_only_sellable_branch_products(): void
    {
        $base = $this->product('Latte');
        $this->recipe($base);
        $optional = $this->product('Coffee with optional milk');
        $group = ModifierGroup::forceCreate([
            'business_id' => $this->business->id, 'name' => 'Extras',
            'min_select' => 0, 'max_select' => 1, 'is_required' => false,
        ]);
        $modifier = Modifier::create([
            'modifier_group_id' => $group->id, 'name' => 'Milk',
            'price_delta' => 0, 'is_active' => true,
        ]);
        foreach ([$base, $optional] as $product) {
            $product->modifierGroups()->attach($group->id);
        }
        RecipeItem::create([
            'branch_id' => $this->branch->id, 'product_id' => null,
            'modifier_id' => $modifier->id, 'ingredient_id' => $this->ingredient->id,
            'quantity_used' => 1,
        ]);
        $this->recipe($this->product('Inactive', active: false));
        $this->recipe($this->product('Unavailable', available: false));
        $deleted = $this->product('Deleted');
        $this->recipe($deleted);
        $deleted->delete();
        $otherBranch = Branch::factory()->create(['business_id' => $this->business->id]);
        $this->recipe($this->product('Only another branch recipe'), $otherBranch->id);

        $response = $this->actingAs($this->user)->getJson($this->url());
        $response->assertOk()->assertJsonCount(2, 'data')
            ->assertJsonPath('branch_id', $this->branch->id)
            ->assertJsonPath('ingredient_id', $this->ingredient->id)
            ->assertJsonPath('meta.next_after_id', null);
        $this->assertSame([$base->id, $optional->id], array_column($response->json('data'), 'id'));
        $this->assertArrayNotHasKey('available_servings', $response->json('data.0'));
        $this->assertDatabaseCount('stock_movements', 0);
    }

    public function test_permission_branch_and_business_authorization_are_required(): void
    {
        $this->getJson($this->url())->assertUnauthorized();
        $this->user->revokePermissionTo('inventory.view');
        $this->actingAs($this->user)->getJson($this->url())->assertForbidden();
        $this->user->givePermissionTo('inventory.view');
        $other = Branch::factory()->create(['business_id' => $this->business->id]);
        $this->getJson("/api/v1/ingredients/{$this->ingredient->id}/products?branch_id={$other->id}")
            ->assertForbidden();
        $this->user->givePermissionTo('branches.view-all');
        $this->getJson("/api/v1/ingredients/{$this->ingredient->id}/products?branch_id={$other->id}")
            ->assertNotFound();
        $foreign = Branch::factory()->create();
        // Shared tenant middleware rejects a foreign branch before ingredient lookup.
        $this->getJson("/api/v1/ingredients/{$this->ingredient->id}/products?branch_id={$foreign->id}")
            ->assertForbidden()->assertJsonPath('message', 'You do not have access to that branch.');
    }

    public function test_keyset_pages_are_bounded_without_duplicate_product_names(): void
    {
        $ids = [];
        for ($i = 0; $i < 21; $i++) {
            $product = $this->product("Coffee {$i}");
            $this->recipe($product);
            $ids[] = $product->id;
        }
        $first = $this->actingAs($this->user)->getJson($this->url());
        $first->assertOk()->assertJsonCount(20, 'data')
            ->assertJsonPath('meta.per_page', 20)
            ->assertJsonPath('meta.next_after_id', $ids[19]);
        $next = $this->getJson($this->url('&after_id='.$ids[19]));
        $next->assertOk()->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.id', $ids[20])
            ->assertJsonPath('meta.next_after_id', null);
    }

    public function test_invalid_cursor_is_rejected(): void
    {
        $this->actingAs($this->user)->getJson($this->url('&after_id=-1'))
            ->assertUnprocessable();
        $this->getJson($this->url('&after_id=invalid'))->assertUnprocessable();
    }
}
