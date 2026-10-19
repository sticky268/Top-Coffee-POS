<?php

namespace App\Services\Reports;

use App\Models\Order;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\DB;

/** Sale-cohort profitability. Only immutable line costs and ledger reversals are used. */
final class ProfitReportService
{
    private const MONEY = ['gross', 'discounts', 'reconciliation', 'tax', 'additional', 'refunds', 'refund_tax', 'non_sales_refunds', 'revenue'];

    public function __construct(private SalesReportService $sales) {}

    private function emptyRow(int|string $id, string $name): array
    {
        return ['id' => $id, 'name' => $name, 'quantity' => 0, 'lines' => 0, 'unknown_cost_lines' => 0,
            'legacy_category_lines' => 0, 'cost_micros' => 0, 'reversed_micros' => 0]
            + array_fill_keys(self::MONEY, 0);
    }

    private function add(array &$target, array $line): void
    {
        foreach (array_merge(self::MONEY, ['quantity', 'lines', 'unknown_cost_lines', 'legacy_category_lines', 'cost_micros', 'reversed_micros']) as $key) {
            $target[$key] += $line[$key];
        }
    }

    /** Fixed-size batches, no per-line SQL and no current-recipe cost lookup. */
    private function lines(array $c, string $from, string $to): \Generator
    {
        $unfiltered = $c;
        unset($unfiltered['input']['category_id']); // Item category, not whole-order membership.
        $last = 0;
        while (true) {
            $orders = $this->sales->selected($unfiltered, $from, $to)->where('orders.id', '>', $last)
                ->orderBy('orders.id')->limit(250)->get(['orders.*']);
            if ($orders->isEmpty()) break;
            $ids = $orders->pluck('id');
            $items = DB::table('order_items')->whereIn('order_id', $ids)->orderBy('id')
                ->select('order_items.*')->selectRaw('CASE WHEN ingredient_cost IS NULL THEN NULL ELSE CAST(ROUND(ingredient_cost * 1000000, 0) AS SIGNED) END AS historical_cost_micros')
                ->get()->groupBy('order_id');
            $refunds = DB::table('payment_refunds')->join('payments', 'payments.id', '=', 'payment_refunds.payment_id')
                ->whereIn('payments.order_id', $ids)->selectRaw("payments.order_id, SUM(".ReportMoney::sql('payment_refunds.amount').") AS cents, MAX(CASE WHEN inventory_disposition = 'restock' THEN 1 ELSE 0 END) AS restocked")
                ->groupBy('payments.order_id')->get()->keyBy('order_id');
            $ledger = DB::table('stock_movements')->whereIn('reference_id', $ids)
                ->where('reference_type', (new Order)->getMorphClass())->where('type', 'sale_deduction')
                ->whereIn('branch_id', $c['branches']->pluck('id'))
                ->selectRaw('reference_id, ingredient_id, SUM(CAST(ROUND(quantity * 1000, 0) AS SIGNED)) AS net_quantity, MIN(quantity) AS minimum')
                ->groupBy('reference_id', 'ingredient_id')->get()->groupBy('reference_id');
            foreach ($orders as $order) {
                $last = (int) $order->id;
                $rows = $items->get($order->id, collect());
                if ($rows->isEmpty()) {
                    // Corrupt/legacy sales must not silently disappear from revenue.
                    $rows = collect([(object) ['id' => 0, 'product_id' => 0, 'product_name' => 'Unattributed sale',
                        'quantity' => 0, 'unit_price' => '0.00', 'historical_cost_micros' => null,
                        'sale_category_captured' => false, 'sale_category_id' => null, 'sale_category_name' => null]]);
                }
                $weights = $rows->mapWithKeys(fn ($r) => [$r->id => max(0, ReportMoney::cents((string) $r->unit_price) * (int) $r->quantity)])->all();
                $total = ReportMoney::cents((string) $order->total);
                $tax = ReportMoney::cents((string) $order->tax_total);
                $extra = ReportMoney::cents((string) $order->supplemental_total);
                $refund = (int) ($refunds[$order->id]->cents ?? 0);
                $saleRefund = min($refund, max(0, $total + $extra));
                $refundTax = ReportAllocation::ratio($saleRefund, $tax, $total + $extra);
                $values = ['gross' => ReportMoney::cents((string) $order->subtotal),
                    'discounts' => ReportMoney::cents((string) $order->discount_total), 'tax' => $tax,
                    'additional' => $extra, 'refunds' => $saleRefund - $refundTax, 'refund_tax' => $refundTax,
                    'non_sales_refunds' => $refund - $saleRefund,
                    'revenue' => $total - $tax + $extra - $saleRefund + $refundTax];
                // Allocate components once, then derive revenue. Independently splitting
                // revenue puts tied discount cents on the opposite item.
                $values['reconciliation'] = $total - $tax - $values['gross'] + $values['discounts'];
                $allocated = array_map(fn ($amount) => ReportAllocation::split($amount, $weights), $values);
                $allocated['discounts'] = ReportAllocation::split($values['discounts'], $allocated['gross']);
                $base = [];
                foreach ($weights as $id => $_) {
                    $base[$id] = $allocated['gross'][$id] - $allocated['discounts'][$id];
                }
                $reconciled = $values['reconciliation'] === 0 ? $base
                    : ReportAllocation::split($total - $tax, array_map(fn ($n) => max(0, $n), $base));
                $net = [];
                foreach ($base as $id => $amount) {
                    $allocated['reconciliation'][$id] = $reconciled[$id] - $amount;
                    $net[$id] = $reconciled[$id] + $allocated['additional'][$id];
                }
                // Full refunds cancel every item's recorded net sale, including
                // legacy reconciliation residuals. Partial refunds use net weights.
                $allocated['refunds'] = $saleRefund === $total + $extra
                    ? $net : ReportAllocation::split($values['refunds'], array_map(fn ($n) => max(0, $n), $net));
                foreach ($net as $id => $amount) $allocated['revenue'][$id] = $amount - $allocated['refunds'][$id];
                $restocked = (bool) ($refunds[$order->id]->restocked ?? false);
                $movements = $ledger->get($order->id, collect());
                $verifiedRestock = $restocked && $order->inventory_disposed_at !== null && $refund >= $total + $extra
                    && $movements->isNotEmpty() && $movements->every(fn ($r) => (int) $r->net_quantity === 0)
                    && $movements->contains(fn ($r) => (string) $r->minimum < 0);
                foreach ($rows as $item) {
                    $category = ! $item->sale_category_captured ? 'legacy' : ($item->sale_category_id === null ? 'none' : (string) $item->sale_category_id);
                    if (isset($c['input']['category_id']) && $category !== (string) $c['input']['category_id']) continue;
                    if (isset($c['input']['product_id']) && (int) $item->product_id !== (int) $c['input']['product_id']) continue;
                    if (isset($c['input']['profit_category']) && $category !== $c['input']['profit_category']) continue;
                    $cost = $item->historical_cost_micros === null ? null : (int) $item->historical_cost_micros;
                    $unknown = $cost === null || $cost < 0 || ($restocked && ! $verifiedRestock);
                    $line = $this->emptyRow((int) $item->product_id, $item->product_name ?: 'Archived product #'.$item->product_id);
                    foreach (self::MONEY as $key) $line[$key] = $allocated[$key][$item->id];
                    $line['quantity'] = (int) $item->quantity;
                    $line['lines'] = 1;
                    $line['unknown_cost_lines'] = $unknown ? 1 : 0;
                    $line['legacy_category_lines'] = $category === 'legacy' ? 1 : 0;
                    $line['cost_micros'] = $unknown || $verifiedRestock ? 0 : $cost;
                    $line['reversed_micros'] = $verifiedRestock && $cost !== null && $cost >= 0 ? $cost : 0;
                    $branch = $c['branches']->firstWhere('id', $order->branch_id);
                    yield $line + ['category_key' => $category,
                        'category_name' => $category === 'legacy' ? 'Historical category unknown' : ($item->sale_category_name ?: 'Uncategorised'),
                        'branch_id' => (int) $order->branch_id, 'branch_name' => $branch->name,
                        'order_id' => (int) $order->id, 'order_number' => $order->order_number,
                        'item_id' => (int) $item->id, 'cost_reason' => $unknown ? ($restocked && ! $verifiedRestock ? 'Restock ledger requires review' : 'Historical recipe cost unavailable') : null,
                        'occurred_at_local' => CarbonImmutable::parse($order->completed_at ?? $order->created_at, 'UTC')->setTimezone($branch->timezone ?: 'UTC')->format('Y-m-d H:i:s P')];
                }
            }
        }
    }

    private function aggregate(array $c, string $from, string $to, bool $branchesOnly = false): array
    {
        $summary = $this->emptyRow('all', 'All selected sales');
        $products = $categories = $branches = [];
        foreach ($this->lines($c, $from, $to) as $line) {
            $this->add($summary, $line);
            foreach (($branchesOnly ? ['branches' => [$line['branch_id'], $line['branch_name']]] : ['products' => [$line['id'], $line['name']], 'categories' => [$line['category_key'], $line['category_name']], 'branches' => [$line['branch_id'], $line['branch_name']]]) as $kind => [$id, $name]) {
                ${$kind}[$id] ??= $this->emptyRow($id, $name);
                $this->add(${$kind}[$id], $line);
            }
        }
        return compact('summary', 'products', 'categories', 'branches');
    }

    private function present(array $row, ?array $previous = null): array
    {
        $known = $row['unknown_cost_lines'] === 0;
        $revenueMicros = $row['revenue'] * 10000;
        $profit = $revenueMicros - $row['cost_micros'];
        $out = $row;
        unset($out['cost_micros'], $out['reversed_micros']);
        foreach (self::MONEY as $key) $out[$key] = ReportMoney::decimal($row[$key]);
        $out['known_cogs'] = ReportAllocation::decimal($row['cost_micros']);
        $out['cogs'] = $known ? ReportAllocation::decimal($row['cost_micros']) : null;
        $out['reversed_cogs'] = ReportAllocation::decimal($row['reversed_micros']);
        $out['gross_profit'] = $known ? ReportAllocation::decimal($profit) : null;
        $out['margin_percent'] = $known && $revenueMicros > 0 ? ReportMoney::decimal(ReportAllocation::ratio($profit, 10000, $revenueMicros)) : null;
        if ($previous !== null) {
            $out['comparisons'] = [];
            foreach (array_merge(self::MONEY, ['quantity', 'cogs', 'gross_profit']) as $metric) {
                $a = $metric === 'cogs' ? $row['cost_micros']
                    : ($metric === 'gross_profit' ? $profit : $row[$metric]);
                $b = $metric === 'cogs' ? $previous['cost_micros']
                    : ($metric === 'gross_profit' ? $previous['revenue'] * 10000 - $previous['cost_micros'] : $previous[$metric]);
                $out['comparisons'][$metric] = in_array($metric, ['cogs', 'gross_profit'], true) && (! $known || $previous['unknown_cost_lines'] > 0)
                    ? null : (in_array($metric, ['cogs', 'gross_profit'], true) ? [] : ReportMoney::comparison($a, $b));
                if (in_array($metric, ['cogs', 'gross_profit'], true) && $out['comparisons'][$metric] !== null) {
                    $out['comparisons'][$metric] = [
                        'previous' => ReportAllocation::decimal($b), 'delta' => ReportAllocation::decimal($a - $b),
                        'percent' => $b === 0 ? null : ReportMoney::decimal(ReportAllocation::ratio($a - $b, 10000, abs($b))),
                        'status' => $b === 0 ? ($a === 0 ? 'unchanged' : 'new') : 'comparable'];
                }
                if ($metric === 'quantity' && $out['comparisons'][$metric] !== null) {
                    $out['comparisons'][$metric] = ReportMoney::comparison($a * 100, $b * 100);
                    $out['comparisons'][$metric]['previous'] = $b;
                    $out['comparisons'][$metric]['delta'] = $a - $b;
                }
            }
            $oldMargin = $previous['unknown_cost_lines'] === 0 && $previous['revenue'] > 0
                ? ReportAllocation::ratio($previous['revenue'] * 10000 - $previous['cost_micros'], 10000, $previous['revenue'] * 10000) : null;
            $out['margin_change_points'] = $out['margin_percent'] === null || $oldMargin === null ? null : ReportMoney::decimal(ReportMoney::cents($out['margin_percent']) - $oldMargin);
        }
        return $out;
    }

    public function report(array $c): array
    {
        $p = $c['period'];
        $current = $this->aggregate($c, $p->from, $p->to);
        $previous = $this->aggregate($c, $p->previousFrom, $p->previousTo);
        $result = [];
        foreach (['summary', 'products', 'categories', 'branches'] as $kind) {
            if ($kind === 'summary') {
                $result[$kind] = $this->present($current[$kind], $previous[$kind]);
                continue;
            }
            // Include disappeared sellers so a fall to zero is visible.
            foreach ($previous[$kind] as $id => $row) $current[$kind][$id] ??= $this->emptyRow($id, $row['name']);
            ksort($current[$kind]);
            $result[$kind] = array_values(array_map(fn ($row) => $this->present($row, $previous[$kind][$row['id']] ?? $this->emptyRow($row['id'], $row['name'])), $current[$kind]));
        }
        $selling = array_values(array_filter($result['products'], fn ($r) => $r['quantity'] > 0));
        $known = array_filter($selling, fn ($r) => $r['cogs'] !== null && ReportMoney::cents($r['revenue']) > 0);
        $knownRevenue = array_sum(array_map(fn ($r) => ReportMoney::cents($r['revenue']), $known));
        $knownProfit = array_sum(array_map(fn ($r) => ReportAllocation::micros($r['gross_profit']), $known));
        $marginThreshold = $knownRevenue > 0 ? ReportAllocation::ratio($knownProfit, 10000, $knownRevenue * 10000) : null;
        foreach ($result['products'] as &$row) {
            $row['popularity_percent'] = $current['summary']['quantity'] > 0 ? ReportMoney::decimal(ReportAllocation::ratio($row['quantity'], 10000, $current['summary']['quantity'])) : '0.00';
            $highPopularity = $row['quantity'] * count($selling) >= $current['summary']['quantity'];
            $row['performance'] = $row['quantity'] === 0 ? 'no_sales' : ($row['cogs'] === null ? 'cost_missing' : ($row['margin_percent'] === null || $marginThreshold === null ? 'no_net_revenue'
                : ($highPopularity ? (ReportMoney::cents($row['margin_percent']) >= $marginThreshold ? 'star' : 'volume') : (ReportMoney::cents($row['margin_percent']) >= $marginThreshold ? 'opportunity' : 'review'))));
        }
        unset($row);
        $ranked = array_values(array_filter($result['products'], fn ($r) => $r['quantity'] > 0));
        usort($ranked, fn ($a, $b) => ($b['quantity'] <=> $a['quantity']) ?: ($a['id'] <=> $b['id']));
        $result['best_sellers'] = array_slice($ranked, 0, 10);
        usort($ranked, fn ($a, $b) => ($a['quantity'] <=> $b['quantity']) ?: ($a['id'] <=> $b['id']));
        $result['slow_sellers'] = array_slice($ranked, 0, 10);
        $soldIds = array_keys(array_filter($current['products'], fn ($r) => $r['quantity'] > 0));
        $result['unsold_products'] = DB::table('products')->join('branch_product', 'branch_product.product_id', '=', 'products.id')
            ->whereIn('branch_product.branch_id', $c['branches']->pluck('id'))->where('branch_product.is_available', true)
            ->where('products.business_id', $c['business_id'])->where('products.is_active', true)->whereNull('products.deleted_at')->whereNotIn('products.id', $soldIds)
            ->when(isset($c['input']['category_id']), fn ($q) => $q->where('products.category_id', $c['input']['category_id']))
            ->distinct()->orderBy('products.id')->get(['products.id', 'products.name'])->all();
        $result['meta'] = $this->meta($c, $marginThreshold, count($selling), $current['summary']['quantity']);
        return $result;
    }

    private function meta(array $c, ?int $marginThreshold = null, int $sellingCount = 0, int $quantity = 0): array
    {
        $p = $c['period'];
        return ['date_from' => $p->from, 'date_to' => $p->to, 'previous_from' => $p->previousFrom, 'previous_to' => $p->previousTo,
            'branches' => $c['branches']->map(fn ($b) => ['id' => (int) $b->id, 'name' => $b->name, 'timezone' => $b->timezone ?: 'UTC'])->values(),
            'cashier_id' => $c['input']['cashier_id'] ?? null,
            'cashier_name' => isset($c['input']['cashier_id']) ? $c['cashiers']->firstWhere('id', $c['input']['cashier_id'])->name : null,
            'category_id' => $c['input']['category_id'] ?? null,
            'category_name' => isset($c['input']['category_id']) ? $c['categories']->firstWhere('id', $c['input']['category_id'])->name : null,
            'currency' => 'USD', 'generated_at' => CarbonImmutable::now('UTC')->toIso8601String(),
            'margin_threshold_percent' => $marginThreshold === null ? null : ReportMoney::decimal($marginThreshold),
            'popularity_threshold_units' => $sellingCount === 0 ? 0 : intdiv($quantity + $sellingCount - 1, $sellingCount),
            'basis' => 'Fully paid completed sales by branch-local completion date. Revenue excludes recorded tax. Gross, tax and additional charges use original line price × quantity weights with largest remainders. Discounts use allocated gross weights; revenue is derived from allocated components. Recorded total reconciliation preserves legacy discrepancies. Partial refunds excluding tax use net sale weights; full refunds cancel each line net sale. Refunds up to the sale value reduce revenue; any surplus is a non-sales refund. Refund tax is proportional to original tax; additional charges have no recorded tax. Adjustments follow the original sale. This is gross profit, before operating expenses.',
            'cost_basis' => 'Sale-time line recipe cost includes variants and modifiers. Full restock reversals require a balanced stock_movements ledger; consumed and wasted items retain their cost. Missing costs make profit and margin incomplete. Historical categories are never backfilled from today’s catalogue.',
            'unsold_basis' => 'Currently active, available catalogue products with no units sold in this selection; availability history is not recorded. A cashier filter means no sales by that cashier.'];
    }

    /** Shared allocation engine without catalogue queries or product ranking. */
    public function branchComparison(array $c): array
    {
        $p = $c['period'];
        $current = $this->aggregate($c, $p->from, $p->to, true);
        $previous = $this->aggregate($c, $p->previousFrom, $p->previousTo, true);
        $rows = [];
        foreach ($c['branches'] as $branch) {
            $id = (int) $branch->id;
            $rows[$id] = $this->present($current['branches'][$id] ?? $this->emptyRow($id, $branch->name),
                $previous['branches'][$id] ?? $this->emptyRow($id, $branch->name));
            $rows[$id]['timezone'] = $branch->timezone ?: 'UTC';
        }
        uasort($rows, fn ($a, $b) => (ReportMoney::cents($b['revenue']) <=> ReportMoney::cents($a['revenue'])) ?: ($a['id'] <=> $b['id']));
        $total = $current['summary']['revenue'];
        $shares = $total > 0 ? ReportAllocation::split(10000, array_map(fn ($r) => ReportMoney::cents($r['revenue']), $rows)) : [];
        $position = 0; $rank = 0; $lastRevenue = null;
        foreach ($rows as $id => &$row) {
            $position++;
            if ($row['revenue'] !== $lastRevenue) $rank = $position;
            $row['revenue_rank'] = $total > 0 ? $rank : null;
            $row['revenue_share_percent'] = isset($shares[$id]) ? ReportMoney::decimal($shares[$id]) : null;
            $lastRevenue = $row['revenue'];
        }
        unset($row);
        return ['summary' => $this->present($current['summary'], $previous['summary']), 'branches' => array_values($rows),
            'meta' => $this->meta($c) + ['comparison_basis' => 'Accessible branches include zero-activity and archived branches. Revenue rank is descending with tied ranks; revenue shares sum to 100% after largest-remainder rounding, or are unavailable when total revenue is zero. Growth compares selected calendar dates in each branch timezone with pinned previous dates; it is not same-store or trading-day-normalised growth. Cashier and historical item-category filters apply. Zero previous revenue is new activity, not infinite growth. Margin changes are percentage points. Missing historical costs make COGS, profit and margin unavailable. Synced sales only.']];
    }

    public function details(array $c, int $page): array
    {
        $rows = []; $total = 0;
        foreach ($this->lines($c, $c['period']->from, $c['period']->to) as $line) {
            if ($total >= ($page - 1) * 50 && count($rows) < 50) $rows[] = $this->present($line);
            $total++;
        }
        return ['rows' => $rows, 'total' => $total, 'page' => $page, 'per_page' => 50];
    }
}
