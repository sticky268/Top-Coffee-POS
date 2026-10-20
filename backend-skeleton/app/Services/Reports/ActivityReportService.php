<?php

namespace App\Services\Reports;

use App\Models\Order;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\DB;

/** Bounded, bulk-loaded sale cohorts. Money remains integer cents throughout. */
final class ActivityReportService
{
    private const MONEY = ['sales', 'discounts', 'refunds', 'net_sales'];
    private const COUNTS = ['orders', 'discounted_orders', 'refunded_orders', 'voids'];

    public function __construct(private SalesReportService $sales) {}

    private function empty(): array
    {
        return array_fill_keys(array_merge(self::MONEY, self::COUNTS), 0);
    }

    private function local($stamp, $branch): CarbonImmutable
    {
        return CarbonImmutable::parse($stamp, 'UTC')->setTimezone($branch->timezone ?: 'UTC');
    }

    private function records(array $c, string $from, string $to): \Generator
    {
        $branches = $c['branches']->keyBy('id');
        $last = 0;
        while (true) {
            $orders = $this->sales->selected($c, $from, $to)->where('orders.id', '>', $last)
                ->orderBy('orders.id')->limit(250)->get(['orders.*']);
            if ($orders->isEmpty()) break;
            $refunds = DB::table('payment_refunds')->join('payments', 'payments.id', '=', 'payment_refunds.payment_id')
                ->leftJoin('users', fn ($j) => $j->on('users.id', '=', 'payment_refunds.processed_by')->where('users.business_id', $c['business_id']))
                ->whereIn('payments.order_id', $orders->pluck('id'))
                ->select('payments.order_id', 'payment_refunds.amount', 'users.name AS actor')->get()->groupBy('order_id');
            foreach ($orders as $o) {
                $last = (int) $o->id;
                $returned = $refunds->get($o->id, collect());
                $refund = $returned->sum(fn ($r) => ReportMoney::cents((string) $r->amount));
                $sales = ReportMoney::cents((string) $o->total) + ReportMoney::cents((string) $o->supplemental_total);
                $discount = ReportMoney::cents((string) $o->discount_total);
                $local = $this->local($o->completed_at ?? $o->created_at, $branches[$o->branch_id]);
                yield ['order_id' => (int) $o->id, 'order_number' => $o->order_number, 'branch_id' => (int) $o->branch_id,
                    'branch_name' => $branches[$o->branch_id]->name, 'cashier_id' => (int) $o->user_id,
                    'weekday' => $local->dayOfWeekIso, 'hour' => $local->hour,
                    'occurred_at_local' => $local->format('Y-m-d H:i:s P'),
                    'actors' => $returned->pluck('actor')->map(fn ($n) => $n ?? 'Unknown refund actor')->unique()->values()->all(),
                    'kind' => 'sale', 'sales' => $sales, 'discounts' => $discount, 'refunds' => $refund,
                    'net_sales' => $sales - $refund, 'orders' => 1, 'discounted_orders' => $discount > 0 ? 1 : 0,
                    'refunded_orders' => $refund > 0 ? 1 : 0, 'voids' => 0];
            }
        }
        // Cancellation timestamps/actors come from append-only evidence, never updated_at.
        $events = DB::table('audit_logs')->where('action', 'order.cancelled')
            ->where('business_id', $c['business_id'])
            ->where('auditable_type', (new Order)->getMorphClass())
            ->selectRaw('auditable_id, MIN(id) AS event_id')->groupBy('auditable_id');
        $q = DB::table('orders')->joinSub($events, 'first_void', 'first_void.auditable_id', '=', 'orders.id')
            ->join('audit_logs', 'audit_logs.id', '=', 'first_void.event_id')
            ->leftJoin('users AS actor', fn ($j) => $j->on('actor.id', '=', 'audit_logs.user_id')->where('actor.business_id', $c['business_id']))
            ->whereIn('orders.branch_id', $branches->keys())->where('orders.status', 'cancelled');
        if (isset($c['input']['cashier_id'])) $q->where('orders.user_id', $c['input']['cashier_id']);
        if (isset($c['input']['category_id'])) $q->whereExists(fn ($i) => $i->selectRaw('1')->from('order_items')
            ->join('products', 'products.id', '=', 'order_items.product_id')->whereColumn('order_items.order_id', 'orders.id')
            ->where('products.category_id', $c['input']['category_id']));
        $q->where(function ($q) use ($branches, $from, $to) {
            foreach ($branches as $b) {
                [$start, $until] = ReportPeriod::window($from, $to, $b->timezone ?: 'UTC');
                $q->orWhere(fn ($q) => $q->where('orders.branch_id', $b->id)
                    ->where('audit_logs.created_at', '>=', $start)->where('audit_logs.created_at', '<', $until));
            }
            if ($branches->isEmpty()) $q->whereRaw('1 = 0');
        });
        $last = 0;
        while (true) {
            $rows = (clone $q)->where('orders.id', '>', $last)->orderBy('orders.id')->limit(250)
                ->get(['orders.id', 'orders.order_number', 'orders.branch_id', 'orders.user_id', 'audit_logs.created_at AS voided_at', 'actor.name AS actor_name']);
            if ($rows->isEmpty()) break;
            foreach ($rows as $o) {
                $last = (int) $o->id;
                $local = $this->local($o->voided_at, $branches[$o->branch_id]);
                yield ['order_id' => (int) $o->id, 'order_number' => $o->order_number, 'branch_id' => (int) $o->branch_id,
                    'branch_name' => $branches[$o->branch_id]->name, 'cashier_id' => (int) $o->user_id,
                    'weekday' => $local->dayOfWeekIso, 'hour' => $local->hour, 'occurred_at_local' => $local->format('Y-m-d H:i:s P'),
                    'actors' => [$o->actor_name ?? 'Unknown void actor'], 'kind' => 'void'] + ['voids' => 1] + $this->empty();
            }
        }
    }

    private function aggregate(array $c, string $from, string $to): array
    {
        $summary = $this->empty(); $cashiers = []; $cells = [];
        for ($d = 1; $d <= 7; $d++) for ($h = 0; $h < 24; $h++) $cells["$d:$h"] = $this->empty();
        foreach ($this->records($c, $from, $to) as $r) {
            $cashiers[$r['cashier_id']] ??= $this->empty();
            foreach (array_keys($summary) as $key) {
                $summary[$key] += $r[$key];
                $cashiers[$r['cashier_id']][$key] += $r[$key];
                $cells[$r['weekday'].':'.$r['hour']][$key] += $r[$key];
            }
        }
        return compact('summary', 'cashiers', 'cells');
    }

    private function rate(array $row, string $metric): ?int
    {
        $denominator = $metric === 'voids' ? $row['orders'] + $row['voids'] : $row['orders'];
        return $denominator === 0 ? null : ReportAllocation::ratio($row[$metric], 10000, $denominator);
    }

    private function present(array $row, array $previous): array
    {
        $out = $row; $out['comparisons'] = [];
        foreach (array_merge(self::MONEY, self::COUNTS) as $key) {
            $comparison = ReportMoney::comparison($row[$key], $previous[$key]);
            if (in_array($key, self::MONEY, true)) $out[$key] = ReportMoney::decimal($row[$key]);
            else { $comparison['previous'] = $previous[$key]; $comparison['delta'] = $row[$key] - $previous[$key]; }
            $out['comparisons'][$key] = $comparison;
        }
        foreach (['discounted_orders', 'refunded_orders', 'voids'] as $metric) {
            $a = $this->rate($row, $metric); $b = $this->rate($previous, $metric);
            $out[$metric.'_rate'] = $a === null ? null : ReportMoney::decimal($a);
            $out[$metric.'_previous_rate'] = $b === null ? null : ReportMoney::decimal($b);
            $out[$metric.'_change_points'] = $a === null || $b === null ? null : ReportMoney::decimal($a - $b);
        }
        return $out;
    }

    public function report(array $c): array
    {
        $p = $c['period'];
        $current = $this->aggregate($c, $p->from, $p->to);
        $previous = $this->aggregate($c, $p->previousFrom, $p->previousTo);
        $peerContext = $c; unset($peerContext['input']['cashier_id']);
        $peerTotal = isset($c['input']['cashier_id']) ? $this->aggregate($peerContext, $p->from, $p->to)['summary'] : $current['summary'];
        $ids = array_unique(array_merge(array_keys($current['cashiers']), array_keys($previous['cashiers'])));
        $names = DB::table('users')->where('business_id', $c['business_id'])->whereIn('id', $ids)->pluck('name', 'id');
        sort($ids); $cashiers = [];
        foreach ($ids as $id) {
            $row = $current['cashiers'][$id] ?? $this->empty();
            $view = $this->present($row, $previous['cashiers'][$id] ?? $this->empty());
            $view += ['id' => $id, 'name' => $names[$id] ?? 'Archived cashier #'.$id, 'flags' => []];
            $peer = []; foreach ($row as $key => $value) $peer[$key] = $peerTotal[$key] - $value;
            foreach (['discounted_orders', 'refunded_orders', 'voids'] as $metric) {
                $n = $row['orders'] + ($metric === 'voids' ? $row['voids'] : 0);
                $peerN = $peer['orders'] + ($metric === 'voids' ? $peer['voids'] : 0);
                $rate = $this->rate($row, $metric); $peerRate = $this->rate($peer, $metric);
                if ($n >= 20 && $peerN >= 20 && $rate >= 1000 && $rate > 2 * $peerRate) $view['flags'][] = $metric;
            }
            $cashiers[] = $view;
        }
        $cells = [];
        foreach ($current['cells'] as $key => $row) {
            [$weekday, $hour] = array_map('intval', explode(':', $key));
            $cells[] = ['weekday' => $weekday, 'hour' => $hour] + $this->present($row, $previous['cells'][$key]);
        }
        return ['summary' => $this->present($current['summary'], $previous['summary']), 'cashiers' => $cashiers, 'cells' => $cells,
            'meta' => ['date_from' => $p->from, 'date_to' => $p->to, 'previous_from' => $p->previousFrom, 'previous_to' => $p->previousTo,
                'branches' => $c['branches']->map(fn ($b) => ['id' => (int) $b->id, 'name' => $b->name, 'timezone' => $b->timezone ?: 'UTC'])->values(),
                'cashier_name' => isset($c['input']['cashier_id']) ? $c['cashiers']->firstWhere('id', $c['input']['cashier_id'])->name : null,
                'category_name' => isset($c['input']['category_id']) ? $c['categories']->firstWhere('id', $c['input']['category_id'])->name : null,
                'basis' => 'Paid completed sales, including tax and additional charges. Refunds follow the original sale even when processed later. Whole orders use the selected current catalogue category. Cashiers are original order owners, not necessarily refund/void actors. Voids use the first recorded cancellation audit event; legacy cancellations without audit evidence have no reliable event date and are excluded. Heatmaps combine repeated DST hours and keep missing hours at zero; comparisons are totals, not normalised for weekday exposure. Unsynced offline orders are absent.',
                'heatmap_max_net_cents' => max(1, max(array_map(fn ($r) => abs($r['net_sales']), $current['cells']))),
                'heatmap_max_orders' => max(1, max(array_column($cells, 'orders'))),
                'flag_basis' => 'Review prompts only: at least 20 own and 20 peer observations, rate at least 10% and greater than twice the other cashiers rate. Discounts/refunds use paid orders; voids use paid orders plus voids. Peer scope preserves branch/category filters and ignores the cashier filter. No flag is a fraud finding.',
                'generated_at' => CarbonImmutable::now('UTC')->toIso8601String()]];
    }

    public function details(array $c): array
    {
        $input = $c['input']; $page = (int) ($input['page'] ?? 1); $total = 0; $rows = [];
        foreach ($this->records($c, $c['period']->from, $c['period']->to) as $r) {
            if (isset($input['weekday']) && $r['weekday'] !== (int) $input['weekday']) continue;
            if (isset($input['hour']) && $r['hour'] !== (int) $input['hour']) continue;
            if (isset($input['source_cashier']) && $r['cashier_id'] !== (int) $input['source_cashier']) continue;
            $kind = $input['activity_kind'] ?? 'orders';
            if ($kind === 'voids' ? $r['kind'] !== 'void' : $r['kind'] !== 'sale') continue;
            if ($kind === 'discounts' && $r['discounted_orders'] === 0) continue;
            if ($kind === 'refunds' && $r['refunded_orders'] === 0) continue;
            if ($total >= ($page - 1) * 50 && count($rows) < 50) $rows[] = $this->present($r, $this->empty());
            $total++;
        }
        return ['rows' => $rows, 'total' => $total, 'page' => $page, 'per_page' => 50];
    }
}
