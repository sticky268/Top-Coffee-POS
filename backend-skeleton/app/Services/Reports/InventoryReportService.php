<?php

namespace App\Services\Reports;

use App\Models\Order;
use Brick\Math\BigDecimal as Decimal;
use Brick\Math\RoundingMode;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\DB;

/** Read-only inventory: ledger balances and immutable sale recipe expectations. */
final class InventoryReportService
{
    public function __construct(private SalesReportService $sales) {}
    private function n(mixed $v = '0'): Decimal { return Decimal::of((string) $v); }
    private function text(mixed $v, int $scale = 3): ?string
    {
        return $v === null ? null : (string) $this->n($v)->toScale($scale, RoundingMode::HALF_UP);
    }
    private function comparison(mixed $a, mixed $b, int $scale): ?array
    {
        if ($a === null || $b === null) return null;
        $a = $this->n($a); $b = $this->n($b); $delta = $a->minus($b);
        return ['previous' => $this->text($b, $scale), 'delta' => $this->text($delta, $scale),
            'percent' => $b->isZero() ? null : (string) $delta->multipliedBy(100)->dividedBy($b->abs(), 2, RoundingMode::HALF_UP),
            'status' => $b->isZero() ? ($a->isZero() ? 'unchanged' : 'new') : 'comparable'];
    }
    private function ingredients(array $c)
    {
        return DB::table('ingredients')->join('units', 'units.id', '=', 'ingredients.unit_id')
            ->whereIn('ingredients.branch_id', $c['branches']->pluck('id'))->orderBy('ingredients.id')
            ->get(['ingredients.id', 'ingredients.branch_id', 'ingredients.name', 'ingredients.reorder_threshold',
                'ingredients.is_active', 'ingredients.deleted_at', 'ingredients.created_at', 'units.abbreviation AS unit']);
    }
    private function empty(): array
    {
        return array_fill_keys(['opening', 'closing', 'waste', 'known_waste_cost', 'deducted', 'returned', 'known_expected', 'adjustments'], $this->n())
            + ['value' => $this->n(), 'unknown_waste' => 0, 'ledger_review' => false];
    }
    private function ledger(array $c, string $from, string $to): array
    {
        $result = [];
        foreach ($c['branches'] as $branch) {
            [$start, $until] = ReportPeriod::window($from, $to, $branch->timezone ?: 'UTC');
            $q = DB::table('stock_movements')->where('branch_id', $branch->id)->where('created_at', '<', $until)
                ->orderBy('created_at')->orderBy('id');
            foreach ($q->lazy(250) as $m) {
                $id = (int) $m->ingredient_id; $r = $result[$id] ?? $this->empty();
                $quantity = $this->n($m->quantity); $old = $r['closing']; $next = $old->plus($quantity);
                if ($m->created_at < $start) $r['opening'] = $next;
                // Recorded historical costs preserve refund-to-waste reclassification:
                // a return and its matching waste must have zero net book value.
                $cost = $m->unit_cost === null || $this->n($m->unit_cost)->isNegative() ? null : $this->n($m->unit_cost);
                $r['value'] = $r['value'] === null || $cost === null ? null : $r['value']->plus($quantity->multipliedBy($cost));
                if ($next->isNegative() || ($r['value'] !== null && $r['value']->isNegative())) {
                    $r['ledger_review'] = true; $r['value'] = null;
                }
                if ($next->isZero()) $r['value'] = $this->n();
                $r['closing'] = $next;
                if ($m->created_at >= $start) {
                    if ($m->type === 'wastage' && $quantity->isNegative()) {
                        $r['waste'] = $r['waste']->plus($quantity->abs());
                        if ($m->unit_cost === null || $this->n($m->unit_cost)->isNegative()) $r['unknown_waste']++;
                        else $r['known_waste_cost'] = $r['known_waste_cost']->plus($quantity->abs()->multipliedBy($m->unit_cost));
                    }
                    if ($m->type === 'adjustment') $r['adjustments'] = $r['adjustments']->plus($quantity);
                }
                $result[$id] = $r;
            }
        }
        return $result;
    }
    /** Gross deductions, not net returns. Both sides use the same paid-sale cohort. */
    private function usage(array $c, string $from, string $to): \Generator
    {
        $allowed = DB::table('ingredients')->whereIn('branch_id', $c['branches']->pluck('id'))->pluck('branch_id', 'id');
        $last = 0;
        while (true) {
            $orders = $this->sales->selected($c, $from, $to)->where('orders.id', '>', $last)->orderBy('orders.id')->limit(250)->get(['orders.*']);
            if ($orders->isEmpty()) break;
            $ids = $orders->pluck('id');
            $items = DB::table('order_items')->whereIn('order_id', $ids)->orderBy('id')->get()->groupBy('order_id');
            $movements = DB::table('stock_movements')->whereIn('reference_id', $ids)->where('reference_type', (new Order)->getMorphClass())
                ->where('type', 'sale_deduction')->whereIn('branch_id', $c['branches']->pluck('id'))->orderBy('id')->get()->groupBy('reference_id');
            foreach ($orders as $order) {
                $last = (int) $order->id; $expected = []; $actual = []; $returns = []; $missing = 0;
                $branch = $c['branches']->firstWhere('id', $order->branch_id);
                [, $until] = ReportPeriod::window($from, $to, $branch->timezone ?: 'UTC');
                $lines = $items->get($order->id, collect());
                if ($lines->isEmpty()) $missing++;
                foreach ($lines as $item) {
                    $snapshot = $item->recipe_usage_snapshot === null ? null : json_decode($item->recipe_usage_snapshot, true);
                    if (! is_array($snapshot) || $snapshot === []) { $missing++; continue; }
                    foreach ($snapshot as $entry) {
                        if (! is_array($entry) || ! isset($entry['ingredient_id'], $entry['quantity']) ||
                            ! preg_match('/^\d+\.\d{3}$/D', (string) $entry['quantity'])) { $missing++; continue; }
                        $id = (int) $entry['ingredient_id'];
                        if ((int) $allowed->get($id, 0) !== (int) $order->branch_id) { $missing++; continue; }
                        $expected[$id] = ($expected[$id] ?? $this->n())->plus($entry['quantity']);
                    }
                }
                foreach ($movements->get($order->id, collect()) as $m) {
                    if ((int) $m->branch_id !== (int) $order->branch_id || $m->created_at >= $until) continue;
                    $id = (int) $m->ingredient_id; $q = $this->n($m->quantity);
                    if ($q->isNegative()) $actual[$id] = ($actual[$id] ?? $this->n())->plus($q->abs());
                    else $returns[$id] = ($returns[$id] ?? $this->n())->plus($q);
                }
                yield compact('order', 'expected', 'actual', 'returns', 'missing');
            }
        }
    }
    private function period(array $c, string $from, string $to): array
    {
        $rows = $this->ledger($c, $from, $to); $missing = 0; $sales = 0;
        foreach ($this->usage($c, $from, $to) as $u) {
            $missing += $u['missing']; $sales++;
            foreach (['expected' => 'known_expected', 'actual' => 'deducted', 'returns' => 'returned'] as $source => $key) {
                foreach ($u[$source] as $id => $q) {
                    $rows[$id] ??= $this->empty(); $rows[$id][$key] = $rows[$id][$key]->plus($q);
                }
            }
        }
        return compact('rows', 'missing', 'sales');
    }
    private function present(array $r, bool $complete): array
    {
        $out = [];
        foreach (['opening', 'closing', 'waste', 'deducted', 'returned', 'known_expected', 'adjustments'] as $key) $out[$key] = $this->text($r[$key]);
        $out['value'] = $this->text($r['value'], 6);
        $out['known_waste_cost'] = $this->text($r['known_waste_cost'], 6);
        $out['waste_cost'] = $r['unknown_waste'] > 0 ? null : $out['known_waste_cost'];
        $out['expected'] = $complete ? $out['known_expected'] : null;
        $out['variance'] = $complete ? $this->text($r['deducted']->minus($r['known_expected'])) : null;
        $out['ledger_review'] = $r['ledger_review']; $out['unknown_waste_movements'] = $r['unknown_waste'];
        return $out;
    }
    public function report(array $c): array
    {
        $p = $c['period']; $a = $this->period($c, $p->from, $p->to); $b = $this->period($c, $p->previousFrom, $p->previousTo);
        $summary = $old = ['value' => $this->n(), 'waste_cost' => $this->n(), 'known_value' => $this->n(), 'known_waste_cost' => $this->n(),
            'unknown_value_items' => 0, 'low_stock_items' => 0, 'variance_items' => 0, 'ledger_review_items' => 0];
        $rows = []; $catalogue = $this->ingredients($c);
        foreach ($catalogue as $i) {
            [, $until] = ReportPeriod::window($p->from, $p->to, $c['branches']->firstWhere('id', $i->branch_id)->timezone ?: 'UTC');
            if ($i->created_at >= $until && ! isset($a['rows'][$i->id]) && ! isset($b['rows'][$i->id])) continue;
            $current = $a['rows'][$i->id] ?? $this->empty(); $previous = $b['rows'][$i->id] ?? $this->empty();
            $row = $this->present($current, $a['missing'] === 0); $prev = $this->present($previous, $b['missing'] === 0);
            foreach (['summary' => [$row, $current, $p->to], 'old' => [$prev, $previous, $p->previousTo]] as $target => [$view, $raw, $end]) {
                [, $until] = ReportPeriod::window($end, $end, $c['branches']->firstWhere('id', $i->branch_id)->timezone ?: 'UTC');
                $exists = $i->created_at < $until || isset(($target === 'summary' ? $a : $b)['rows'][$i->id]);
                if (! $exists) continue;
                if ($view['value'] === null) ${$target}['unknown_value_items']++;
                else ${$target}['known_value'] = ${$target}['known_value']->plus($view['value']);
                ${$target}['known_waste_cost'] = ${$target}['known_waste_cost']->plus($view['known_waste_cost']);
                if ($view['waste_cost'] === null) ${$target}['waste_cost'] = null;
                if ($i->is_active && $i->deleted_at === null && $raw['closing']->isLessThanOrEqualTo($i->reorder_threshold)) ${$target}['low_stock_items']++;
                if ($view['variance'] !== null && ! $this->n($view['variance'])->isZero()) ${$target}['variance_items']++;
                if ($view['ledger_review']) ${$target}['ledger_review_items']++;
            }
            $branch = $c['branches']->firstWhere('id', $i->branch_id);
            $rows[] = ['id' => (int) $i->id, 'name' => $i->name, 'branch_id' => (int) $i->branch_id, 'branch_name' => $branch->name,
                'unit' => $i->unit, 'active' => (bool) $i->is_active && $i->deleted_at === null,
                'threshold' => $this->text($i->reorder_threshold), 'low_stock' => (bool) $i->is_active && $i->deleted_at === null && $current['closing']->isLessThanOrEqualTo($i->reorder_threshold),
                'comparisons' => collect(['opening', 'closing', 'value', 'waste', 'waste_cost', 'deducted', 'returned', 'expected', 'variance', 'adjustments'])->mapWithKeys(fn ($k) => [$k => $this->comparison($row[$k], $prev[$k], in_array($k, ['value', 'waste_cost'], true) ? 6 : 3)])->all()] + $row;
        }
        foreach (['summary', 'old'] as $key) {
            ${$key}['value'] = ${$key}['unknown_value_items'] > 0 ? null : ${$key}['known_value'];
            if (${$key}['waste_cost'] !== null) ${$key}['waste_cost'] = ${$key}['known_waste_cost'];
        }
        $summary['sales'] = $a['sales']; $old['sales'] = $b['sales'];
        $summary['missing_recipe_lines'] = $a['missing']; $old['missing_recipe_lines'] = $b['missing'];
        if ($a['missing'] > 0) $summary['variance_items'] = null;
        if ($b['missing'] > 0) $old['variance_items'] = null;
        $summary['comparisons'] = [];
        foreach (array_keys($old) as $key) {
            $scale = in_array($key, ['value', 'waste_cost', 'known_value', 'known_waste_cost'], true) ? 6 : 0;
            $summary['comparisons'][$key] = $this->comparison($summary[$key], $old[$key], $scale);
            if ($scale === 6) $summary[$key] = $this->text($summary[$key], 6);
        }
        return ['summary' => $summary, 'ingredients' => $rows, 'meta' => [
            'date_from' => $p->from, 'date_to' => $p->to, 'previous_from' => $p->previousFrom, 'previous_to' => $p->previousTo,
            'branches' => $c['branches']->map(fn ($r) => ['id' => (int) $r->id, 'name' => $r->name, 'timezone' => $r->timezone ?: 'UTC'])->values(),
            'cashier_name' => isset($c['input']['cashier_id']) ? $c['cashiers']->firstWhere('id', $c['input']['cashier_id'])->name : null,
            'category_name' => isset($c['input']['category_id']) ? $c['categories']->firstWhere('id', $c['input']['category_id'])->name : null,
            'basis' => 'Stock balances and recorded-cost valuation replay stock_movements through each branch-local end date; current_stock and average_unit_cost caches are not used. Unknown movement costs make valuation unknown until stock is exhausted. Cost-only edits outside the ledger do not revalue historical stock. Low-stock flags use current active status and reorder thresholds. Waste and adjustments/transfers are branch-wide event-date movements. Sales usage alone follows the selected fully paid completed whole orders (current catalogue category), comparing original gross sale deductions against immutable recipe quantities captured at completion. Returns through the end date are shown separately, not deducted from gross usage. Missing historical recipe lines make complete theory and variance unavailable; known expected quantities remain visible. This is a ledger/recipe discrepancy, not a physical stocktake or a fraud finding. Different ingredient units are never summed. Unsynced offline sales are absent.',
            'generated_at' => CarbonImmutable::now('UTC')->toIso8601String()]];
    }
    public function details(array $c): array
    {
        $id = (int) $c['input']['ingredient_id'];
        $i = $this->ingredients($c)->firstWhere('id', $id); abort_unless($i, 403, 'Ingredient access denied.');
        $branch = $c['branches']->firstWhere('id', $i->branch_id);
        [$start, $until] = ReportPeriod::window($c['period']->from, $c['period']->to, $branch->timezone ?: 'UTC');
        $page = (int) ($c['input']['page'] ?? 1); $kind = $c['input']['inventory_kind'] ?? 'ledger';
        $rows = []; $total = 0;
        if ($kind === 'sales') {
            foreach ($this->usage($c, $c['period']->from, $c['period']->to) as $u) {
                if ((int) $u['order']->branch_id !== (int) $i->branch_id) continue;
                if (! isset($u['expected'][$id]) && ! isset($u['actual'][$id]) && ! isset($u['returns'][$id]) && $u['missing'] === 0) continue;
                if ($total >= ($page - 1) * 50 && count($rows) < 50) $rows[] = [
                    'order_id' => (int) $u['order']->id, 'order_number' => $u['order']->order_number,
                    'expected' => $u['missing'] > 0 ? null : $this->text($u['expected'][$id] ?? $this->n()),
                    'deducted' => $this->text($u['actual'][$id] ?? $this->n()), 'returned' => $this->text($u['returns'][$id] ?? $this->n()),
                    'missing_recipe_lines' => $u['missing']];
                $total++;
            }
        } else {
            $q = DB::table('stock_movements')->leftJoin('users', fn ($j) => $j->on('users.id', '=', 'stock_movements.created_by')->where('users.business_id', $c['business_id']))
                ->where('stock_movements.branch_id', $i->branch_id)->where('ingredient_id', $id)
                ->where('stock_movements.created_at', '<', $kind === 'opening' ? $start : $until);
            if (in_array($kind, ['ledger', 'waste'], true)) $q->where('stock_movements.created_at', '>=', $start);
            if ($kind === 'waste') $q->where('type', 'wastage')->where('quantity', '<', 0);
            $total = (clone $q)->count();
            $rows = $q->orderBy('stock_movements.created_at')->orderBy('stock_movements.id')->offset(($page - 1) * 50)->limit(50)
                ->get(['stock_movements.*', 'users.name AS actor'])->map(function ($m) use ($branch) {
                    return ['movement_id' => (int) $m->id, 'type' => $m->type, 'quantity' => $this->text($m->quantity), 'unit_cost' => $this->text($m->unit_cost, 6),
                        'reason' => $m->reason, 'actor' => $m->actor ?? 'Archived operator', 'reference_type' => $m->reference_type, 'reference_id' => $m->reference_id,
                        'occurred_at_local' => CarbonImmutable::parse($m->created_at, 'UTC')->setTimezone($branch->timezone ?: 'UTC')->format('Y-m-d H:i:s P')];
                })->all();
        }
        return ['ingredient' => ['id' => $id, 'name' => $i->name, 'unit' => $i->unit, 'branch_name' => $branch->name],
            'rows' => $rows, 'total' => $total, 'page' => $page, 'per_page' => 50, 'kind' => $kind];
    }
}
