<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\Product;
use App\Models\ProductVariant;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Validator;
use Illuminate\Validation\Rule;

class ProductController extends Controller
{
    /**
     * GET /api/v1/products?category_id=1&branch_id=1
     *
     * Returns active products actually sellable at the authenticated user's
     * branch context: a product only appears if it has a branch_product
     * pivot row for that branch with is_available = true (matching how
     * CategoryProductSeeder assigns products to branches — presence in the
     * pivot is what makes a product sellable there at all, not just an
     * on/off flag on the product itself).
     *
     * Branch resolution/authorization mirrors CategoryController::index()
     * exactly (see that file for the full rationale) — duplicated here
     * rather than extracted into a shared trait, since that would mean
     * touching the already-completed Categories API without a genuine
     * dependency reason to.
     *
     * No specific permission required beyond auth:sanctum, for the same
     * reason as Categories: the seeded cashier role has no 'products.*'
     * permission, and browsing the catalog is what the POS screen needs
     * this endpoint for.
     */
    public function index(Request $request)
    {
        $validator = Validator::make($request->query(), [
            'branch_id' => 'nullable|integer|exists:branches,id',
            'category_id' => 'nullable|integer|exists:categories,id',
        ]);

        if ($validator->fails()) {
            return response()->json([
                'success' => false,
                'message' => 'Validation failed',
                'errors' => $validator->errors(),
            ], 422);
        }

        $user = $request->user();
        $branchId = $request->query('branch_id');
        $categoryId = $request->query('category_id');

        if ($branchId !== null) {
            $canAccessBranch = $user->can('branches.view-all')
                || $user->branches()->where('branches.id', $branchId)->exists();

            if (! $canAccessBranch) {
                return response()->json([
                    'success' => false,
                    'message' => 'You do not have access to that branch',
                ], 403);
            }
        } else {
            $branch = $user->branches()->wherePivot('is_primary', true)->first()
                ?? $user->branches()->first();

            if (! $branch) {
                return response()->json([
                    'success' => false,
                    'message' => 'No branch is assigned to this user',
                ], 422);
            }

            $branchId = $branch->id;
        }

        $products = Product::query()
            ->where('is_active', true)
            ->when($categoryId, fn ($query) => $query->where('category_id', $categoryId))
            ->whereHas('branches', function ($query) use ($branchId) {
                $query->where('branches.id', $branchId)
                    ->where('branch_product.is_available', true);
            })
            ->with([
                'category:id,name',
                'branches' => function ($query) use ($branchId) {
                    // Scoped to the resolved branch only, so
                    // $product->branches->first() below is unambiguous —
                    // this is purely to pull that branch's price_override,
                    // not a general branch listing.
                    $query->where('branches.id', $branchId);
                },
                'variants' => function ($query) {
                    $query->where('is_active', true)->orderBy('name');
                },
            ])
            ->orderBy('name')
            ->get();

        $data = $products->map(function (Product $product) {
            $branchPivot = $product->branches->first()?->pivot;
            $effectivePrice = ($branchPivot && $branchPivot->price_override !== null)
                ? (float) $branchPivot->price_override
                : (float) $product->base_price;

            return [
                'id' => $product->id,
                'name' => $product->name,
                'sku' => $product->sku,
                'description' => $product->description,
                'category' => $product->category ? [
                    'id' => $product->category->id,
                    'name' => $product->category->name,
                ] : null,
                'price' => $effectivePrice,
                // Each variant's price is the absolute resolved price
                // (branch-effective base + variant delta), not just the
                // raw delta — so the Flutter POS screen can display it
                // directly without repeating this arithmetic client-side.
                'variants' => $product->variants->map(fn ($variant) => [
                    'id' => $variant->id,
                    'name' => $variant->name,
                    'price' => $effectivePrice + (float) $variant->price_delta,
                ])->values(),
            ];
        });

        return response()->json([
            'success' => true,
            'data' => $data,
        ]);
    }

    /**
     * POST /api/v1/products
     *
     * Requires 'products.manage' (seeded on admin + manager, not cashier —
     * see RolePermissionSeeder). Branch authorization is enforced only on
     * the `branches` array in the payload: in this schema a product is a
     * shared, catalog-wide entity (base_price/category/etc. aren't owned
     * by any one branch — only branch_product availability/pricing is
     * branch-specific), so that's the one place "must not
     * create/update products for unauthorized branches" is actually
     * meaningful to enforce. A user without branches.view-all may only
     * assign availability for branches they're assigned to.
     */
    public function store(Request $request)
    {
        if (! $request->user()->can('products.manage')) {
            return response()->json([
                'success' => false,
                'message' => 'You do not have permission to manage products',
            ], 403);
        }

        $validator = Validator::make($request->all(), [
            'name' => 'required|string|max:255',
            'category_id' => 'required|integer|exists:categories,id',
            'sku' => 'nullable|string|max:255|unique:products,sku',
            'description' => 'nullable|string',
            'base_price' => 'required|numeric|min:0',
            'is_active' => 'nullable|boolean',

            'variants' => 'nullable|array',
            'variants.*.name' => 'required_with:variants|string|max:255',
            'variants.*.sku' => 'nullable|string|max:255',
            'variants.*.price_delta' => 'required_with:variants|numeric',
            'variants.*.is_active' => 'nullable|boolean',

            'branches' => 'nullable|array',
            'branches.*.branch_id' => 'required_with:branches|integer|exists:branches,id',
            'branches.*.price_override' => 'nullable|numeric|min:0',
            'branches.*.is_available' => 'nullable|boolean',
        ]);

        if ($validator->fails()) {
            return response()->json([
                'success' => false,
                'message' => 'Validation failed',
                'errors' => $validator->errors(),
            ], 422);
        }

        $user = $request->user();
        $branchesInput = $request->input('branches', []);

        if (! empty($branchesInput) && ! $user->can('branches.view-all')) {
            $allowedBranchIds = $user->branches()->pluck('branches.id')->all();
            foreach ($branchesInput as $branchInput) {
                if (! in_array((int) $branchInput['branch_id'], $allowedBranchIds, true)) {
                    return response()->json([
                        'success' => false,
                        'message' => "You do not have access to branch {$branchInput['branch_id']}",
                    ], 403);
                }
            }
        }

        $product = DB::transaction(function () use ($request, $branchesInput) {
            $product = Product::create([
                'category_id' => $request->input('category_id'),
                'name' => $request->input('name'),
                'sku' => $request->input('sku'),
                'description' => $request->input('description'),
                'base_price' => $request->input('base_price'),
                'is_active' => $request->boolean('is_active', true),
            ]);

            foreach ($request->input('variants', []) as $variantInput) {
                ProductVariant::create([
                    'product_id' => $product->id,
                    'name' => $variantInput['name'],
                    'sku' => $variantInput['sku'] ?? null,
                    'price_delta' => $variantInput['price_delta'],
                    'is_active' => $variantInput['is_active'] ?? true,
                ]);
            }

            foreach ($branchesInput as $branchInput) {
                $product->branches()->attach($branchInput['branch_id'], [
                    'price_override' => $branchInput['price_override'] ?? null,
                    'is_available' => $branchInput['is_available'] ?? true,
                ]);
            }

            return $product;
        });

        return response()->json([
            'success' => true,
            'data' => $this->present($product),
        ], 201);
    }

    /**
     * PATCH /api/v1/products/{product}
     *
     * Partial update — every field is optional ('sometimes'). Same
     * 'products.manage' + per-branch authorization as store().
     *
     * Variants: the payload's variant list is an upsert, not a replace —
     * an entry with a matching `id` updates that variant, an entry
     * without one creates a new variant, and any of the product's
     * existing variants NOT mentioned in the payload are left completely
     * untouched (never deleted). This mirrors the product-level
     * disable-don't-delete approach: order_items.product_variant_id uses
     * nullOnDelete(), so hard-deleting a variant is schema-safe but would
     * erase which variant a historical order line actually was. To
     * deactivate a variant, include it with `is_active: false` — GET
     * /products already filters variants on is_active, so this has the
     * same effect as removing it from the live catalog without losing
     * history.
     *
     * Branches: also an upsert per branch_id given (attach if new,
     * updateExistingPivot if already present) — deliberately NOT a
     * wholesale sync(), which would delete any branch_product row not
     * mentioned in the payload. That matters for authorization safety
     * too: a manager restricted to one branch must not be able to wipe
     * out another branch's availability just by submitting an update
     * that doesn't happen to mention it.
     */
    public function update(Request $request, Product $product)
    {
        if (! $request->user()->can('products.manage')) {
            return response()->json([
                'success' => false,
                'message' => 'You do not have permission to manage products',
            ], 403);
        }

        $validator = Validator::make($request->all(), [
            'name' => 'sometimes|required|string|max:255',
            'category_id' => 'sometimes|required|integer|exists:categories,id',
            'sku' => ['sometimes', 'nullable', 'string', 'max:255', Rule::unique('products', 'sku')->ignore($product->id)],
            'description' => 'sometimes|nullable|string',
            'base_price' => 'sometimes|required|numeric|min:0',
            'is_active' => 'sometimes|boolean',

            'variants' => 'sometimes|array',
            'variants.*.id' => 'nullable|integer|exists:product_variants,id',
            'variants.*.name' => 'required_with:variants|string|max:255',
            'variants.*.sku' => 'nullable|string|max:255',
            'variants.*.price_delta' => 'required_with:variants|numeric',
            'variants.*.is_active' => 'nullable|boolean',

            'branches' => 'sometimes|array',
            'branches.*.branch_id' => 'required_with:branches|integer|exists:branches,id',
            'branches.*.price_override' => 'nullable|numeric|min:0',
            'branches.*.is_available' => 'nullable|boolean',
        ]);

        if ($validator->fails()) {
            return response()->json([
                'success' => false,
                'message' => 'Validation failed',
                'errors' => $validator->errors(),
            ], 422);
        }

        $user = $request->user();
        $branchesInput = $request->input('branches');

        if ($branchesInput !== null && ! $user->can('branches.view-all')) {
            $allowedBranchIds = $user->branches()->pluck('branches.id')->all();
            foreach ($branchesInput as $branchInput) {
                if (! in_array((int) $branchInput['branch_id'], $allowedBranchIds, true)) {
                    return response()->json([
                        'success' => false,
                        'message' => "You do not have access to branch {$branchInput['branch_id']}",
                    ], 403);
                }
            }
        }

        DB::transaction(function () use ($request, $product, $branchesInput) {
            $product->fill($request->only(['category_id', 'name', 'sku', 'description', 'base_price']));
            if ($request->has('is_active')) {
                $product->is_active = $request->boolean('is_active');
            }
            $product->save();

            if ($request->has('variants')) {
                foreach ($request->input('variants') as $variantInput) {
                    $variant = ! empty($variantInput['id'])
                        ? ProductVariant::where('id', $variantInput['id'])->where('product_id', $product->id)->first()
                        : null;

                    if ($variant) {
                        $variant->update([
                            'name' => $variantInput['name'],
                            'sku' => $variantInput['sku'] ?? $variant->sku,
                            'price_delta' => $variantInput['price_delta'],
                            'is_active' => $variantInput['is_active'] ?? $variant->is_active,
                        ]);
                        continue;
                    }

                    ProductVariant::create([
                        'product_id' => $product->id,
                        'name' => $variantInput['name'],
                        'sku' => $variantInput['sku'] ?? null,
                        'price_delta' => $variantInput['price_delta'],
                        'is_active' => $variantInput['is_active'] ?? true,
                    ]);
                }
            }

            if ($branchesInput !== null) {
                foreach ($branchesInput as $branchInput) {
                    $alreadyLinked = $product->branches()->where('branches.id', $branchInput['branch_id'])->exists();
                    $pivotValues = [
                        'price_override' => $branchInput['price_override'] ?? null,
                        'is_available' => $branchInput['is_available'] ?? true,
                    ];

                    if ($alreadyLinked) {
                        $product->branches()->updateExistingPivot($branchInput['branch_id'], $pivotValues);
                    } else {
                        $product->branches()->attach($branchInput['branch_id'], $pivotValues);
                    }
                }
            }
        });

        return response()->json([
            'success' => true,
            'data' => $this->present($product->fresh()),
        ]);
    }

    /**
     * Full management-view shape for a single product — used by
     * store()/update() only. Deliberately independent of index()'s
     * per-item mapping above (which is branch-resolved and
     * customer-facing) rather than sharing a helper with it, so as not to
     * touch the already-complete, already-tested index() method.
     * Includes ALL variants (even inactive ones) and ALL branch
     * assignments, since this is a management/edit response, not the
     * filtered customer-facing catalog.
     */
    private function present(Product $product): array
    {
        $product->loadMissing(['category:id,name', 'variants', 'branches']);

        return [
            'id' => $product->id,
            'name' => $product->name,
            'sku' => $product->sku,
            'description' => $product->description,
            'base_price' => (float) $product->base_price,
            'is_active' => (bool) $product->is_active,
            'category' => $product->category ? [
                'id' => $product->category->id,
                'name' => $product->category->name,
            ] : null,
            'variants' => $product->variants->map(fn (ProductVariant $variant) => [
                'id' => $variant->id,
                'name' => $variant->name,
                'sku' => $variant->sku,
                'price_delta' => (float) $variant->price_delta,
                'is_active' => (bool) $variant->is_active,
            ])->values(),
            'branches' => $product->branches->map(fn ($branch) => [
                'branch_id' => $branch->id,
                'branch_name' => $branch->name,
                'price_override' => $branch->pivot->price_override !== null ? (float) $branch->pivot->price_override : null,
                'is_available' => (bool) $branch->pivot->is_available,
            ])->values(),
        ];
    }
}
