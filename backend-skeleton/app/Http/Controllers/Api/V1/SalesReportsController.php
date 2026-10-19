<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\Branch;
use App\Services\Reports\ReportPeriod;
use App\Services\Reports\ProfitReportService;
use App\Services\Reports\SalesReportService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class SalesReportsController extends Controller
{
    public function index(Request $request, SalesReportService $service, ProfitReportService $profit)
    {
        abort_unless($request->user()->can('reports.view'), 403, 'You do not have permission to view reports.');
        $input = $request->validate([
            'report' => 'nullable|in:sales,profit',
            'product_id' => 'nullable|integer|min:0',
            'profit_category' => ['nullable', 'regex:/^(legacy|none|[0-9]+)$/'],
            'branch_id' => 'nullable|integer|min:1',
            'cashier_id' => 'nullable|integer|min:1',
            'category_id' => 'nullable|integer|min:1',
            'period' => 'nullable|in:today,yesterday,week,last7,last30,this_month,last_month,month,year,custom',
            'year' => 'required_if:period,month,year|integer|min:2000|max:2100',
            'month' => 'required_if:period,month|integer|min:1|max:12',
            'date_from' => 'required_if:period,custom|date_format:Y-m-d',
            'date_to' => 'required_if:period,custom|date_format:Y-m-d|after_or_equal:date_from',
            'detail' => 'nullable|in:orders,refunds,payments,excluded,event_payments,event_refunds,profit',
            'metric' => 'nullable|in:gross_sales,discounts,tax,total_sales,supplemental_sales,refunds,net_sales,total_orders,average_order_value',
            'method' => 'nullable|in:cash,card,qr,split',
            'page' => 'nullable|integer|min:1|max:1000000',
        ]);
        $user = $request->user();
        $branches = Branch::withTrashed()->where('business_id', $user->business_id)
            ->when(! $user->can('branches.view-all'), fn ($q) => $q->whereIn('id', $user->branches()->select('branches.id')))
            ->orderBy('id')->get(['id', 'name', 'timezone']);
        if (isset($input['branch_id'])) {
            abort_unless($branches->contains('id', $input['branch_id']), 403, 'Branch access denied.');
            $branches = $branches->where('id', $input['branch_id'])->values();
        }
        $period = new ReportPeriod($input, $branches->count() === 1 ? ($branches->first()->timezone ?: 'UTC') : 'UTC');
        $context = $service->context($branches, $period, $input, $user);
        if (($input['report'] ?? 'sales') === 'profit') {
            abort_if(isset($input['detail']) && $input['detail'] !== 'profit', 422, 'Invalid profit source selection.');
            return response()->json(['success' => true, 'data' => DB::transaction(fn () => isset($input['detail'])
                ? $profit->details($context, (int) ($input['page'] ?? 1)) : $profit->report($context))]);
        }
        abort_if(($input['detail'] ?? null) === 'profit', 422, 'Choose the profit report.');
        return response()->json(['success' => true, 'data' => DB::transaction(fn () => isset($input['detail'])
            ? $service->details($context, $input)
            : $service->report($context))]);
    }
}
