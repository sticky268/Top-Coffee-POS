<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\{Product, ModifierGroup, MenuDiscount, Branch, Category, Ingredient};
use App\Services\AuditLogService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;

class MenuManagementController extends Controller
{
    private function authorizeMenu(Request $request): void
    {
        abort_unless($request->user()->can('products.manage'), 403, 'You cannot manage the menu.');
    }

    private function branch(Request $request): int
    {
        $id = $request->integer('branch_id');
        $branch = Branch::findOrFail($id);
        abort_unless((int) $branch->business_id === (int) $request->user()->business_id
            && ($request->user()->can('branches.view-all') || $request->user()->branches()->whereKey($id)->exists()), 403);
        return $id;
    }

    public function index(Request $request)
    {
        $this->authorizeMenu($request);
        $branch = $this->branch($request);
        return response()->json(['data' => [
            'products' => Product::with(['category', 'variants', 'branches' => fn ($q) => $q->where('branches.id', $branch), 'modifierGroups', 'images'])
                ->whereHas('branches', fn ($q) => $q->where('branches.id', $branch))->orderBy('name')->get()->each(function ($product) {
                    foreach ($product->images as $image) $image->setAttribute('url', asset('storage/'.$image->path));
                }),
            'categories' => Category::where(fn ($q) => $q->whereNull('branch_id')->orWhere('branch_id', $branch))->orderBy('sort_order')->get(),
            'modifiers' => ModifierGroup::with(['modifiers.recipeItems', 'products:id,name'])->orderBy('name')->get(),
            'discounts' => MenuDiscount::where(fn ($q) => $q->whereNull('branch_id')->orWhere('branch_id', $branch))->orderBy('name')->get(),
            'ingredients' => Ingredient::where('branch_id', $branch)->orderBy('name')->get(['id', 'name']),
        ]]);
    }

    public function combo(Request $request, ?int $id = null)
    {
        $this->authorizeMenu($request);
        $branch = $this->branch($request);
        $data = $request->validate([
            'name' => 'required|string|max:120', 'category_id' => 'required|integer',
            'base_price' => 'required|decimal:0,2|min:0|max:999999.99', 'is_active' => 'required|boolean',
            'combo_slots' => 'required|array|min:1|max:20', 'combo_slots.*.name' => 'required|string|max:80',
            'combo_slots.*.quantity' => 'required|integer|min:1|max:100',
            'combo_slots.*.choices' => 'required|array|min:1|max:50',
            'combo_slots.*.choices.*.product_id' => 'required|integer',
            'combo_slots.*.choices.*.variant_id' => 'nullable|integer',
            'combo_slots.*.choices.*.extra_price' => 'required|decimal:0,2|min:0|max:99999.99',
        ]);
        $category = Category::findOrFail($data['category_id']);
        abort_if($category->branch_id && (int) $category->branch_id !== $branch, 422, 'Choose a category for this branch.');
        foreach ($data['combo_slots'] as $slot) {
            $ids = array_column($slot['choices'], 'product_id');
            abort_if(count($ids) !== count(array_unique($ids)), 422, 'Each slot must have distinct products.');
            foreach ($slot['choices'] as $choice) {
                $product = Product::whereHas('branches', fn ($q) => $q->where('branches.id', $branch))->findOrFail($choice['product_id']);
                abort_if($product->combo_slots || $product->modifierGroups()->where(fn ($q) => $q->where('is_required', true)->orWhere('min_select', '>', 0))->exists(), 422, 'Choose individual items without required modifiers as combo components.');
                abort_if(isset($choice['variant_id']) && ! $product->variants()->where('is_active', true)->whereKey($choice['variant_id'])->exists(), 422, 'Choose an active size belonging to the component.');
            }
        }
        $combo = DB::transaction(function () use ($request, $id, $data, $branch) {
            $product = $id ? Product::lockForUpdate()->findOrFail($id) : new Product;
            abort_if($id && ! $product->combo_slots, 422, 'This item is not a combo.');
            $before = $product->exists ? $product->toArray() : null;
            $product->fill($data)->save();
            if (! $id) $product->branches()->attach($branch, ['is_available' => true]);
            app(AuditLogService::class)->record($request, $id ? 'combo.updated' : 'combo.created', $product, $before, $product->toArray());
            return $product;
        });
        return response()->json(['data' => $combo], $id ? 200 : 201);
    }

    public function modifier(Request $request, ?int $id = null)
    {
        $this->authorizeMenu($request);
        $branch = $this->branch($request);
        $data = $request->validate([
            'name' => 'required|string|max:120', 'min_select' => 'required|integer|min:0|max:50',
            'max_select' => 'required|integer|min:1|max:50|gte:min_select', 'is_required' => 'required|boolean', 'is_active' => 'sometimes|boolean',
            'product_ids' => 'present|array', 'product_ids.*' => 'integer|distinct',
            'options' => 'required|array|min:1|max:50', 'options.*.id' => 'nullable|integer|distinct',
            'options.*.name' => 'required|string|max:120', 'options.*.price_delta' => 'required|decimal:0,2|min:0|max:99999.99',
            'options.*.is_active' => 'required|boolean', 'options.*.recipe' => 'present|array',
            'options.*.recipe.*.ingredient_id' => 'required|integer|distinct',
            'options.*.recipe.*.quantity_used' => 'required|decimal:0,3|gt:0|max:999999',
        ]);
        $activeCount = collect($data['options'])->where('is_active', true)->count();
        abort_if(($data['is_active'] ?? true) && max($data['min_select'], $data['is_required'] ? 1 : 0) > $activeCount, 422, 'Not enough active options for the required choices.');
        foreach ($data['product_ids'] as $productId) Product::findOrFail($productId);
        foreach ($data['options'] as $option) {
            foreach ($option['recipe'] as $row) Ingredient::where('branch_id', $branch)->findOrFail($row['ingredient_id']);
        }
        $group = DB::transaction(function () use ($id, $data, $branch, $request) {
            $group = $id ? ModifierGroup::lockForUpdate()->findOrFail($id) : new ModifierGroup;
            $before = $group->exists ? $group->load('modifiers')->toArray() : null;
            $group->fill(collect($data)->only(['name', 'min_select', 'max_select', 'is_required', 'is_active'])->all())->save();
            $kept = [];
            foreach ($data['options'] as $option) {
                $modifier = isset($option['id']) ? $group->modifiers()->findOrFail($option['id']) : $group->modifiers()->make();
                $modifier->fill(collect($option)->only(['name', 'price_delta', 'is_active'])->all())->save();
                $kept[] = $modifier->id;
                $modifier->recipeItems()->where('branch_id', $branch)->delete();
                foreach ($option['recipe'] as $row) $modifier->recipeItems()->create($row + ['branch_id' => $branch, 'product_id' => null]);
            }
            // Retain historical identities; omitted options are archived.
            $group->modifiers()->whereNotIn('id', $kept)->update(['is_active' => false]);
            $group->products()->sync($data['product_ids']);
            app(AuditLogService::class)->record($request, 'modifier_group.saved', $group, $before, $group->load('modifiers')->toArray());
            return $group;
        });
        return response()->json(['data' => $group]);
    }

    public function discount(Request $request, ?int $id = null)
    {
        $this->authorizeMenu($request);
        $branch = $this->branch($request);
        $data = $request->validate([
            'name' => 'required|string|max:120', 'type' => ['required', Rule::in(['fixed', 'percent'])],
            'value' => 'required|decimal:0,2|gt:0|max:999999.99', 'is_active' => 'required|boolean',
            'requires_manager' => 'required|boolean', 'starts_on' => 'nullable|date_format:Y-m-d',
            'ends_on' => ['nullable', 'date_format:Y-m-d', ...($request->filled('starts_on') ? ['after_or_equal:starts_on'] : [])],
            'all_branches' => 'required|boolean',
        ]);
        abort_if($data['type'] === 'percent' && \App\Services\OperationService::cents($data['value']) > 10000, 422, 'Percentage cannot exceed 100.');
        abort_if($data['all_branches'] && ! $request->user()->can('branches.view-all'), 403, 'Only a business-wide manager can publish a discount to all branches.');
        $discount = DB::transaction(function () use ($request, $id, $data, $branch) {
            $discount = $id ? MenuDiscount::lockForUpdate()->findOrFail($id) : new MenuDiscount;
            abort_if($id && $discount->branch_id && (int) $discount->branch_id !== $branch, 403);
            abort_if($id && ! $discount->branch_id && ! $request->user()->can('branches.view-all'), 403);
            $before = $discount->exists ? $discount->toArray() : null;
            $discount->fill(collect($data)->except('all_branches')->all());
            $discount->branch_id = $data['all_branches'] ? null : $branch;
            $discount->save();
            app(AuditLogService::class)->record($request, 'menu_discount.saved', $discount, $before, $discount->toArray());
            return $discount;
        });
        return response()->json(['data' => $discount]);
    }

    public function discounts(Request $request)
    {
        $branch = $this->branch($request);
        $today = now(Branch::findOrFail($branch)->timezone ?: 'Asia/Phnom_Penh')->toDateString();
        return response()->json(['data' => MenuDiscount::where('is_active', true)
            ->where(fn ($q) => $q->whereNull('branch_id')->orWhere('branch_id', $branch))
            ->where(fn ($q) => $q->whereNull('starts_on')->orWhere('starts_on', '<=', $today))
            ->where(fn ($q) => $q->whereNull('ends_on')->orWhere('ends_on', '>=', $today))->orderBy('name')->get()]);
    }
}
