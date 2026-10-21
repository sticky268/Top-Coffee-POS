<?php

namespace App\Services;

use App\Models\{Product, ProductVariant, MenuDiscount, Branch};
use Brick\Math\BigDecimal;
use Brick\Math\RoundingMode;

/** Resolves untrusted menu selections for every sale/held-bill edit path. */
class MenuSaleService
{
    public static function cents(mixed $value): int
    {
        return BigDecimal::of((string) $value)->multipliedBy(100)->toScale(0, RoundingMode::HALF_UP)->toInt();
    }

    public static function decimal(int $cents): string
    {
        return BigDecimal::of($cents)->dividedBy(100, 2)->__toString();
    }

    public function product(int $id, int $branch): Product
    {
        $product = Product::where('is_active', true)->whereHas('branches', fn ($q) =>
            $q->where('branches.id', $branch)->where('branch_product.is_available', true))
            ->with(['branches' => fn ($q) => $q->where('branches.id', $branch), 'modifierGroups.modifiers'])->find($id);
        abort_unless($product, 422, "Product {$id} is not available at this branch.");
        return $product;
    }

    public function resolve(array $input, int $branch): array
    {
        $product = $this->product((int) $input['product_id'], $branch);
        $price = self::cents($product->branches->first()->pivot->price_override ?? $product->base_price);
        $variant = isset($input['product_variant_id']) ? ProductVariant::where('product_id', $product->id)
            ->where('is_active', true)->find($input['product_variant_id']) : null;
        abort_if(isset($input['product_variant_id']) && ! $variant, 422, 'Choose an available size.');
        abort_if($product->combo_slots && $variant, 422, 'Combos cannot have size variants.');
        if ($variant) $price += self::cents($variant->price_delta);
        $names = $variant ? [$variant->name] : [];
        $modifierIds = array_map('intval', $input['modifier_ids'] ?? []);
        abort_if(count($modifierIds) !== count(array_unique($modifierIds)), 422, 'A modifier cannot be selected twice.');
        $allowed = [];
        foreach ($product->modifierGroups as $group) {
            $active = $group->modifiers->where('is_active', true);
            $selected = $active->whereIn('id', $modifierIds);
            $minimum = max((int) $group->min_select, $group->is_required ? 1 : 0);
            abort_if($selected->count() < $minimum || $selected->count() > $group->max_select, 422, "Check choices for {$group->name}.");
            foreach ($selected as $modifier) {
                $allowed[] = $modifier->id;
                $price += self::cents($modifier->price_delta);
                $names[] = $modifier->name;
            }
        }
        abort_if(array_diff($modifierIds, $allowed), 422, 'A selected modifier is unavailable.');
        $components = [];
        $selections = $input['combo_selections'] ?? [];
        abort_if(count($selections) !== count($product->combo_slots ?? []), 422, 'Choose each combo component.');
        foreach ($product->combo_slots ?? [] as $i => $slot) {
            $choice = collect($slot['choices'])->first(fn ($c) => (int) $c['product_id'] === (int) ($selections[$i] ?? 0));
            abort_unless($choice, 422, 'A combo selection is no longer offered.');
            $component = $this->product((int) $choice['product_id'], $branch);
            abort_if($component->combo_slots || $component->modifierGroups->contains(fn ($g) => $g->is_required || $g->min_select > 0), 422, 'A combo component requires configuration. Review the combo menu.');
            $componentVariant = isset($choice['variant_id']) ? $component->variants()->where('is_active', true)->find($choice['variant_id']) : null;
            abort_if(isset($choice['variant_id']) && ! $componentVariant, 422, 'A combo size is no longer available.');
            $price += self::cents($choice['extra_price'] ?? 0);
            $components[] = ['product_id' => $component->id, 'variant_id' => $componentVariant?->id,
                'quantity' => (int) $slot['quantity'], 'name' => $component->name,
                'recipe_multiplier' => (string) ($componentVariant?->recipe_multiplier ?? 1)];
            $names[] = $slot['quantity'].' × '.$component->name.($componentVariant ? ' / '.$componentVariant->name : '');
        }
        abort_if($price < 0, 422, 'The configured price cannot be negative.');
        return ['product_id' => $product->id, 'product_variant_id' => $variant?->id,
            'product_name' => $product->name, 'variant_name' => $names ? implode(' · ', $names) : null,
            'quantity' => (int) $input['quantity'], 'unit_price' => self::decimal($price),
            'menu_configuration' => ['modifier_ids' => $allowed, 'components' => $components]];
    }

    public function discount(?int $id, int $subtotal, int $branch, int $manual): int
    {
        if (! $id) return $manual;
        $discount = MenuDiscount::where('is_active', true)->where(fn ($q) => $q->whereNull('branch_id')->orWhere('branch_id', $branch))->find($id);
        abort_unless($discount, 422, 'This discount is unavailable.');
        $today = now(Branch::findOrFail($branch)->timezone ?: 'Asia/Phnom_Penh')->toDateString();
        abort_if(($discount->starts_on && $discount->starts_on > $today) || ($discount->ends_on && $discount->ends_on < $today), 422, 'This discount is outside its scheduled dates.');
        abort_if($discount->requires_manager && ! app(CheckoutControls::class)->manager(auth()->user()), 403, 'A manager must apply this discount.');
        $amount = $discount->type === 'percent'
            ? BigDecimal::of($subtotal)->multipliedBy($discount->value)->dividedBy(100, 0, RoundingMode::HALF_UP)->toInt()
            : self::cents($discount->value);
        return min($subtotal, $amount);
    }
}
