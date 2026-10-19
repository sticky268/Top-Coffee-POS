<?php

namespace App\Services\Reports;

use App\Models\User;
use Carbon\CarbonImmutable;
use Illuminate\Database\Query\Builder;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;

final class SalesReportService
{
    private const SETTLED = "(payments.status = 'completed' OR (payments.status IN ('partially_refunded', 'refunded') AND EXISTS (SELECT 1 FROM payment_refunds WHERE payment_refunds.payment_id = payments.id)))";

    public function context(Collection $branches, ReportPeriod $period, array $input, User $user): array
    {
        $ids = $branches->pluck('id');
        $cashiers = DB::table('users')->where('business_id', $user->business_id)
            ->where(function ($q) use ($ids) {
                $q->whereIn('id', DB::table('user_branch')->whereIn('branch_id', $ids)->select('user_id'))
                    ->orWhereIn('id', DB::table('orders')->whereIn('branch_id', $ids)->select('user_id'));
            })->orderBy('name')->get(['id', 'name']);
        $categories = DB::table('categories')->where('business_id', $user->business_id)
            ->where(fn ($q) => $q->whereNull('branch_id')->orWhereIn('branch_id', $ids))
            ->orderBy('name')->get(['id', 'name']);
        abort_if(isset($input['cashier_id']) && ! $cashiers->contains('id', $input['cashier_id']), 403, 'Cashier access denied.');
        abort_if(isset($input['category_id']) && ! $categories->contains('id', $input['category_id']), 403, 'Category access denied.');
        return compact('branches', 'period', 'input', 'cashiers', 'categories');
    }

    /** All raw builders begin with the authorized branch IDs, including detail queries. */
    private function orders(array $c, bool $paid = true): Builder
    {
        $q = DB::table('orders')->whereIn('orders.branch_id', $c['branches']->pluck('id'))
            ->whereNull('orders.deleted_at')->where('orders.status', 'completed');
        if (isset($c['input']['cashier_id'])) $q->where('orders.user_id', $c['input']['cashier_id']);
        if (isset($c['input']['category_id'])) {
            $q->whereExists(fn ($items) => $items->selectRaw('1')->from('order_items')
                ->join('products', 'products.id', '=', 'order_items.product_id')
                ->whereColumn('order_items.order_id', 'orders.id')
                ->where('products.category_id', $c['input']['category_id']));
        }
        if ($paid) $q->whereRaw('(SELECT COALESCE(SUM('.ReportMoney::sql('payments.amount').'), 0) FROM payments WHERE payments.order_id = orders.id AND '.self::SETTLED.') >= '.ReportMoney::sql('orders.total').' + '.ReportMoney::sql('orders.supplemental_total'));
        return $q;
    }

    private function interval(Builder $q, array $c, string $column, string $from, string $to): Builder
    {
        return $q->where(function ($q) use ($c, $column, $from, $to) {
            // Same calendar dates in each branch's own timezone, including DST.
            foreach ($c['branches'] as $branch) {
                [$start, $until] = ReportPeriod::window($from, $to, $branch->timezone ?: 'UTC');
                $q->orWhere(function ($b) use ($branch, $column, $start, $until) {
                    $b->where('orders.branch_id', $branch->id);
                    if ($column === 'COALESCE(orders.completed_at, orders.created_at)') {
                        // Keep both completion and legacy creation indexes usable.
                        $b->where(fn ($q) => $q->where(fn ($q) => $q->where('orders.completed_at', '>=', $start)->where('orders.completed_at', '<', $until))
                            ->orWhere(fn ($q) => $q->whereNull('orders.completed_at')->where('orders.created_at', '>=', $start)->where('orders.created_at', '<', $until)));
                    } else {
                        $b->where($column, '>=', $start)->where($column, '<', $until);
                    }
                });
            }
            if ($c['branches']->isEmpty()) $q->whereRaw('1 = 0');
        });
    }

    private function selected(array $c, string $from, string $to, bool $paid = true): Builder
    {
        return $this->interval($this->orders($c, $paid), $c, 'COALESCE(orders.completed_at, orders.created_at)', $from, $to);
    }

    private function payments(Builder $orders): Builder
    {
        return DB::table('payments')->whereIn('payments.order_id', (clone $orders)->select('orders.id'))->whereRaw(self::SETTLED);
    }

    private function refunds(Builder $orders): Builder
    {
        return DB::table('payment_refunds')->join('payments', 'payments.id', '=', 'payment_refunds.payment_id')
            ->whereIn('payments.order_id', (clone $orders)->select('orders.id'))->whereRaw(self::SETTLED);
    }

    private function sum(Builder $q, string $column): int
    {
        return (int) $q->selectRaw('COALESCE(SUM('.ReportMoney::sql($column).'), 0) AS amount_cents')->value('amount_cents');
    }

    private function summary(array $c, string $from, string $to): array
    {
        $orders = $this->selected($c, $from, $to);
        $expressions = ['COUNT(*) AS total_orders'];
        foreach (['gross_sales' => 'subtotal', 'discounts' => 'discount_total', 'tax' => 'tax_total', 'total_sales' => 'total', 'supplemental_sales' => 'supplemental_total'] as $name => $column) {
            $expressions[] = 'COALESCE(SUM('.ReportMoney::sql('orders.'.$column)."), 0) AS $name";
        }
        $row = (array) (clone $orders)->selectRaw(implode(', ', $expressions))->first();
        $values = array_map(fn ($value) => (int) $value, $row);
        $values['refunds'] = $this->sum($this->refunds($orders), 'payment_refunds.amount');
        $values['net_sales'] = $values['total_sales'] + $values['supplemental_sales'] - $values['refunds'];
        $values['average_order_value'] = ReportMoney::divide($values['total_sales'], $values['total_orders']);
        $values['excluded_orders'] = $this->selected($c, $from, $to, false)->count() - $values['total_orders'];
        return $values;
    }

    public function report(array $c): array
    {
        $p = $c['period'];
        $current = $this->summary($c, $p->from, $p->to);
        $previous = $this->summary($c, $p->previousFrom, $p->previousTo);
        $summary = $comparisons = [];
        foreach ($current as $key => $value) {
            $isCount = in_array($key, ['total_orders', 'excluded_orders'], true);
            $summary[$key] = $isCount ? $value : ReportMoney::decimal($value);
            $comparisons[$key] = ReportMoney::comparison($isCount ? $value * 100 : $value, $isCount ? $previous[$key] * 100 : $previous[$key]);
            if ($isCount) {
                $comparisons[$key]['previous'] = $previous[$key];
                $comparisons[$key]['delta'] = $value - $previous[$key];
            }
        }
        $orders = $this->selected($c, $p->from, $p->to);
        $methods = $this->paymentMethods($orders);
        $paymentTotal = array_sum(array_column($methods, 'collected_cents'));
        $summary['payment_difference'] = ReportMoney::decimal($paymentTotal - $current['total_sales'] - $current['supplemental_sales']);
        $branches = $c['branches']->map(fn ($b) => ['id' => (int) $b->id, 'name' => $b->name, 'timezone' => $b->timezone ?: 'UTC'])->values();
        return [
            'meta' => ['period' => $p->kind, 'date_from' => $p->from, 'date_to' => $p->to,
                'previous_from' => $p->previousFrom, 'previous_to' => $p->previousTo,
                'today' => $p->today, 'generated_at' => CarbonImmutable::now('UTC')->toIso8601String(),
                'branches' => $branches, 'cashiers' => $c['cashiers'], 'categories' => $c['categories'],
                'cashier_id' => $c['input']['cashier_id'] ?? null, 'category_id' => $c['input']['category_id'] ?? null,
                'category_basis' => 'Whole orders containing a product in the selected current category.',
                'sales_basis' => 'Fully paid completed orders by branch-local completion date; legacy completion dates fall back to creation. Refunds and additional charges follow their original sale.',
                'cash_basis' => 'Collections and refunds by their own branch-local transaction dates. Drawer reconciliation uses whole shifts, independently of sales filters.',
                'currency' => 'USD'],
            'summary' => $summary, 'comparisons' => $comparisons,
            'timeline' => $this->timeline($c),
            'hourly_sales' => $this->hourly($c),
            'top_products' => $this->topProducts($orders),
            'order_types' => $this->orderTypes($orders),
            'payment_methods' => array_map(function ($m) { unset($m['collected_cents']); return $m; }, $methods),
            'cash_flow' => $this->cashFlow($c),
            'shifts' => $this->shifts($c),
        ];
    }

    private function paymentMethods(Builder $orders): array
    {
        $refunds = DB::table('payment_refunds')->selectRaw('payment_id, SUM('.ReportMoney::sql('amount').') AS refund_cents')->groupBy('payment_id');
        return $this->payments($orders)->leftJoinSub($refunds, 'r', 'r.payment_id', '=', 'payments.id')
            ->selectRaw('payments.method, COUNT(*) AS count, SUM('.ReportMoney::sql('payments.amount').') AS collected_cents, SUM(COALESCE(r.refund_cents, 0)) AS refund_cents')
            ->groupBy('payments.method')->orderByRaw('CAST(payments.method AS CHAR)')->get()->map(fn ($r) => [
                'method' => $r->method, 'count' => (int) $r->count,
                'collected_cents' => (int) $r->collected_cents,
                'collected' => ReportMoney::decimal((int) $r->collected_cents),
                'refunds' => ReportMoney::decimal((int) $r->refund_cents),
                'net' => ReportMoney::decimal((int) $r->collected_cents - (int) $r->refund_cents),
            ])->all();
    }

    /** One conditional-aggregate query for all daily/monthly buckets. */
    private function timeline(array $c): array
    {
        $p = $c['period'];
        $monthly = $p->kind === 'year';
        $buckets = [];
        $timelineEnd = $monthly ? CarbonImmutable::parse($p->from)->endOfYear()->toDateString() : $p->to;
        for ($date = CarbonImmutable::parse($p->from); $date->toDateString() <= $timelineEnd; $date = $monthly ? $date->addMonth() : $date->addDay()) {
            $buckets[] = [$date->toDateString(), $monthly ? $date->endOfMonth()->toDateString() : $date->toDateString()];
        }
        $expressions = $bindings = [];
        foreach ($buckets as $i => [$from, $to]) {
            $conditions = [];
            foreach ($c['branches'] as $branch) {
                [$start, $until] = ReportPeriod::window($from, $to, $branch->timezone ?: 'UTC');
                $conditions[] = '(orders.branch_id = ? AND COALESCE(orders.completed_at, orders.created_at) >= ? AND COALESCE(orders.completed_at, orders.created_at) < ?)';
                array_push($bindings, $branch->id, $start, $until);
            }
            $condition = $conditions === [] ? '1 = 0' : implode(' OR ', $conditions);
            $expressions[] = "SUM(CASE WHEN $condition THEN ".ReportMoney::sql('orders.total')." ELSE 0 END) AS bucket_$i";
        }
        $totals = $this->selected($c, $p->from, $p->to)->selectRaw(implode(', ', $expressions), $bindings)->first();
        return array_map(fn ($i) => ['date_from' => $buckets[$i][0], 'date_to' => $buckets[$i][1],
            'total' => ReportMoney::decimal((int) ($totals->{"bucket_$i"} ?? 0)),
            'upcoming' => $monthly && $buckets[$i][0] > $p->today], array_keys($buckets));
    }

    private function topProducts(Builder $orders): array
    {
        return DB::table('order_items')->leftJoin('products', 'products.id', '=', 'order_items.product_id')
            ->whereIn('order_items.order_id', (clone $orders)->select('orders.id'))
            ->selectRaw("order_items.product_id, COALESCE(NULLIF(order_items.product_name, ''), products.name, 'Archived product') AS product_name, SUM(order_items.quantity) AS quantity, SUM(".ReportMoney::sql('order_items.unit_price')." * order_items.quantity) AS cents")
            ->groupBy('order_items.product_id', DB::raw("COALESCE(NULLIF(order_items.product_name, ''), products.name, 'Archived product')"))
            ->orderByDesc('quantity')->orderBy('product_name')->limit(10)->get()->map(fn ($r) => [
                'product_id' => $r->product_id, 'product_name' => $r->product_name,
                'quantity' => (int) $r->quantity, 'total' => ReportMoney::decimal((int) $r->cents),
            ])->all();
    }

    private function orderTypes(Builder $orders): array
    {
        return (clone $orders)->selectRaw('orders.order_type, COUNT(*) AS count, SUM('.ReportMoney::sql('orders.total').') AS cents')
            ->groupBy('orders.order_type')->orderBy('orders.order_type')->get()->map(fn ($r) => [
                'type' => $r->order_type, 'count' => (int) $r->count, 'total' => ReportMoney::decimal((int) $r->cents),
            ])->all();
    }

    private function hourly(array $c): array
    {
        $p = $c['period'];
        if ($p->from !== $p->to || $c['branches']->isEmpty()) return [];
        $buckets = [];
        foreach ($c['branches'] as $branch) {
            $timezone = $branch->timezone ?: 'UTC';
            [$start, $until] = ReportPeriod::window($p->from, $p->to, $timezone);
            $windows = [];
            for ($hour = CarbonImmutable::parse($start, 'UTC'); $hour->toDateTimeString() < $until; $hour = $hour->addHour()) {
                $windows[] = [$hour, $hour->setTimezone($timezone)->format('H:00')];
            }
            $counts = array_count_values(array_column($windows, 1));
            foreach ($windows as [$hour, $label]) {
                // Keep both DST hours visible for one branch. Combined reports combine matching local hours.
                if ($c['branches']->count() === 1 && $counts[$label] > 1) $label .= ' '.$hour->setTimezone($timezone)->format('P');
                $buckets[$label][] = [$branch->id, $hour->toDateTimeString(), $hour->addHour()->toDateTimeString()];
            }
        }
        $expressions = $bindings = [];
        $labels = array_keys($buckets);
        foreach (array_values($buckets) as $i => $windows) {
            $conditions = [];
            foreach ($windows as [$branch, $start, $until]) {
                $conditions[] = '(orders.branch_id = ? AND COALESCE(orders.completed_at, orders.created_at) >= ? AND COALESCE(orders.completed_at, orders.created_at) < ?)';
                array_push($bindings, $branch, $start, $until);
            }
            $expressions[] = 'SUM(CASE WHEN '.implode(' OR ', $conditions).' THEN '.ReportMoney::sql('orders.total')." ELSE 0 END) AS hour_$i";
        }
        $totals = $this->selected($c, $p->from, $p->to)->selectRaw(implode(', ', $expressions), $bindings)->first();
        return array_map(fn ($i) => ['hour' => $labels[$i], 'total' => ReportMoney::decimal((int) ($totals->{"hour_$i"} ?? 0))], array_keys($labels));
    }

    private function eventQuery(array $c, bool $refund = false): Builder
    {
        $orders = $this->orders($c);
        $q = $refund ? $this->refunds($orders) : $this->payments($orders);
        $q->join('orders', 'orders.id', '=', 'payments.order_id');
        return $this->interval($q, $c, $refund ? 'payment_refunds.created_at' : 'payments.created_at', $c['period']->from, $c['period']->to);
    }

    private function cashFlow(array $c): array
    {
        $payments = $this->eventQuery($c);
        $refunds = $this->eventQuery($c, true);
        $collected = $this->sum(clone $payments, 'payments.amount');
        $returned = $this->sum(clone $refunds, 'payment_refunds.amount');
        return ['collected' => ReportMoney::decimal($collected), 'refunds' => ReportMoney::decimal($returned),
            'net' => ReportMoney::decimal($collected - $returned),
            'unassigned_cash_payments' => (clone $payments)->where('payments.method', 'cash')->whereNull('payments.shift_id')->count(),
            'unassigned_cash_refunds' => (clone $refunds)->where('payments.method', 'cash')->whereNull('payment_refunds.shift_id')->count()];
    }

    private function shifts(array $c): array
    {
        $p = $c['period'];
        $q = DB::table('cashier_shifts')->join('users', 'users.id', '=', 'cashier_shifts.user_id')
            ->whereIn('cashier_shifts.branch_id', $c['branches']->pluck('id'));
        $q->where(function ($q) use ($c, $p) {
            foreach ($c['branches'] as $b) {
                [$from, $until] = ReportPeriod::window($p->from, $p->to, $b->timezone ?: 'UTC');
                $q->orWhere(fn ($q) => $q->where('cashier_shifts.branch_id', $b->id)->where('cashier_shifts.created_at', '<', $until)
                    ->where(fn ($q) => $q->whereNull('closed_at')->orWhere('closed_at', '>=', $from)));
            }
            if ($c['branches']->isEmpty()) $q->whereRaw('1 = 0');
        });
        // Whole overlapping shifts, not date-clipped or category/cashier-filtered drawer balances.
        $total = (clone $q)->count();
        $rows = $q->select('cashier_shifts.*', 'users.name AS cashier_name')->orderByDesc('cashier_shifts.id')->limit(50)->get();
        $ids = $rows->pluck('id');
        $paymentTotals = DB::table('payments')->whereIn('shift_id', $ids)->whereRaw(self::SETTLED)->where('method', 'cash')
            ->selectRaw('shift_id, SUM('.ReportMoney::sql('amount').') AS cents')->groupBy('shift_id')->pluck('cents', 'shift_id');
        $refundTotals = DB::table('payment_refunds')->join('payments', 'payments.id', '=', 'payment_refunds.payment_id')
            ->whereIn('payment_refunds.shift_id', $ids)->where('payments.method', 'cash')
            ->selectRaw('payment_refunds.shift_id, SUM('.ReportMoney::sql('payment_refunds.amount').') AS cents')
            ->groupBy('payment_refunds.shift_id')->pluck('cents', 'shift_id');
        $movements = DB::table('cash_movements')->whereIn('shift_id', $ids)->selectRaw("shift_id, SUM(CASE WHEN type = 'in' THEN ".ReportMoney::sql('amount')." ELSE 0 END) AS cash_in, SUM(CASE WHEN type = 'out' THEN ".ReportMoney::sql('amount')." ELSE 0 END) AS cash_out")->groupBy('shift_id')->get()->keyBy('shift_id');
        return ['total' => $total, 'rows' => $rows->map(function ($r) use ($paymentTotals, $refundTotals, $movements) {
            $opening = ReportMoney::cents((string) $r->opening_cash);
            $cash = (int) ($paymentTotals[$r->id] ?? 0);
            $refund = (int) ($refundTotals[$r->id] ?? 0);
            $in = (int) ($movements[$r->id]->cash_in ?? 0);
            $out = (int) ($movements[$r->id]->cash_out ?? 0);
            $expected = $opening + $cash - $refund + $in - $out;
            return ['id' => (int) $r->id, 'branch_id' => (int) $r->branch_id, 'cashier_name' => $r->cashier_name,
                'status' => $r->status, 'opening' => ReportMoney::decimal($opening), 'cash_sales' => ReportMoney::decimal($cash),
                'cash_refunds' => ReportMoney::decimal($refund), 'cash_in' => ReportMoney::decimal($in), 'cash_out' => ReportMoney::decimal($out),
                'expected' => ReportMoney::decimal($expected), 'counted' => $r->counted_cash === null ? null : ReportMoney::decimal(ReportMoney::cents((string) $r->counted_cash)),
                'difference' => $r->counted_cash === null ? null : ReportMoney::decimal(ReportMoney::cents((string) $r->counted_cash) - $expected),
                'recorded_expected' => $r->expected_cash === null ? null : ReportMoney::decimal(ReportMoney::cents((string) $r->expected_cash)),
                'closed_at' => $r->closed_at];
        })->all()];
    }

    public function details(array $c, array $input): array
    {
        $p = $c['period'];
        $kind = $input['detail'];
        $q = $this->selected($c, $p->from, $p->to, $kind !== 'excluded');
        if ($kind === 'excluded') $q->whereNotIn('orders.id', $this->selected($c, $p->from, $p->to)->select('orders.id'));
        $isRefund = in_array($kind, ['refunds', 'event_refunds'], true);
        $isPayment = in_array($kind, ['payments', 'event_payments'], true);
        if ($isRefund || $isPayment) {
            if (str_starts_with($kind, 'event_')) {
                $q = $this->eventQuery($c, $isRefund);
            } else {
                $q = $isRefund ? $this->refunds($q) : $this->payments($q);
                $q->join('orders', 'orders.id', '=', 'payments.order_id');
            }
            if (isset($input['method'])) $q->where('payments.method', $input['method']);
            $q->select('orders.id AS order_id', 'orders.order_number', 'orders.branch_id', 'payments.method',
                $isRefund ? 'payment_refunds.id AS id' : 'payments.id AS id',
                $isRefund ? 'payment_refunds.amount' : 'payments.amount',
                $isRefund ? 'payment_refunds.created_at AS occurred_at' : 'payments.created_at AS occurred_at');
            if ($isRefund) $q->addSelect('payment_refunds.reason');
        } else {
            $metric = $input['metric'] ?? 'total_sales';
            if ($metric === 'discounts') $q->where('orders.discount_total', '>', 0);
            if ($metric === 'tax') $q->where('orders.tax_total', '>', 0);
            if ($metric === 'supplemental_sales') $q->where('orders.supplemental_total', '>', 0);
            $q->select('orders.id AS id', 'orders.id AS order_id', 'orders.order_number', 'orders.branch_id',
                'orders.subtotal AS gross_sales', 'orders.discount_total AS discounts', 'orders.tax_total AS tax',
                'orders.total AS order_total', 'orders.supplemental_total AS supplemental_sales',
                'orders.completed_at AS occurred_at', 'orders.created_at AS legacy_created_at');
            $column = ['gross_sales' => 'orders.subtotal', 'discounts' => 'orders.discount_total',
                'tax' => 'orders.tax_total', 'supplemental_sales' => 'orders.supplemental_total'][$metric] ?? 'orders.total';
            if ($metric === 'net_sales') {
                $q->selectRaw(ReportMoney::sql('orders.total').' + '.ReportMoney::sql('orders.supplemental_total').
                    ' - (SELECT COALESCE(SUM('.ReportMoney::sql('payment_refunds.amount').'), 0) FROM payment_refunds JOIN payments ON payments.id = payment_refunds.payment_id WHERE payments.order_id = orders.id AND '.self::SETTLED.') AS net_cents');
            }
            $q->addSelect(DB::raw($column.' AS amount'));
        }
        $total = (clone $q)->count();
        $page = (int) ($input['page'] ?? 1);
        $branches = $c['branches']->keyBy('id');
        $rows = $q->orderByDesc($isRefund ? 'payment_refunds.id' : ($isPayment ? 'payments.id' : 'orders.id'))
            ->offset(($page - 1) * 50)->limit(50)->get()->map(function ($r) use ($branches) {
                $r = (array) $r;
                $branch = $branches[(int) $r['branch_id']];
                $r['branch_name'] = $branch->name;
                $r['timezone'] = $branch->timezone ?: 'UTC';
                $stamp = $r['occurred_at'] ?? $r['legacy_created_at'] ?? null;
                $r['occurred_at_local'] = $stamp === null ? null : CarbonImmutable::parse($stamp, 'UTC')->setTimezone($r['timezone'])->format('Y-m-d H:i:s P');
                if (isset($r['net_cents'])) { $r['amount'] = ReportMoney::decimal((int) $r['net_cents']); unset($r['net_cents']); }
                foreach (['amount', 'order_total', 'gross_sales', 'discounts', 'tax', 'supplemental_sales'] as $key) {
                    if (isset($r[$key])) $r[$key] = ReportMoney::decimal(ReportMoney::cents((string) $r[$key]));
                }
                return $r;
            });
        return ['rows' => $rows, 'total' => $total, 'page' => $page, 'per_page' => 50];
    }
}
