<?php

namespace App\Services;

use App\Models\Customer;
use App\Models\CustomerLoyaltyAccount;
use App\Models\LoyaltySetting;
use App\Models\LoyaltyTransaction;
use App\Models\Order;
use Illuminate\Support\Facades\DB;

class LoyaltyService
{
    public function reverseForOrder(Order $order, int $actor): void
    {
        $earned = LoyaltyTransaction::where('order_id', $order->id)->where('type', 'earned')->first();
        if (! $earned) return;
        $refunded = (float) DB::table('payment_refunds')->whereIn('payment_id', $order->payments()->select('id'))->sum('amount');
        $ratio = (float) $order->total > 0 ? min(1, $refunded / (float) $order->total) : 1;
        $target = (int) floor($earned->points * $ratio + 0.000001);
        $points = max(0, $target - (int) $order->refunded_loyalty_points);
        if ($points === 0) return;
        $account = CustomerLoyaltyAccount::whereKey($earned->customer_loyalty_account_id)->lockForUpdate()->firstOrFail();
        $removed = min($account->points_balance, $points);
        $account->points_balance -= $removed;
        $account->refund_points_debt += $points - $removed;
        $account->save();
        $order->forceFill(['refunded_loyalty_points' => $target])->save();
        LoyaltyTransaction::create(['customer_loyalty_account_id' => $account->id, 'customer_id' => $order->customer_id, 'branch_id' => $order->branch_id, 'order_id' => $order->id, 'type' => 'adjustment', 'points' => -$removed, 'balance_after' => $account->points_balance, 'description' => 'Refund points reversal; operator #'.$actor]);
    }

    /**
     * Award loyalty points for a completed order.
     *
     * Returns the created transaction, or null when loyalty is disabled,
     * there is no customer, or the order earns zero points.
     */
    public function awardForOrder(Order $order): ?LoyaltyTransaction
    {
        if ($order->customer_id === null) {
            return null;
        }

        $setting = LoyaltySetting::query()
            ->where('branch_id', $order->branch_id)
            ->first();

        if (! $setting || ! $setting->is_enabled) {
            return null;
        }

        $points = (int) floor(
            max(0, (float) $order->total)
            * (float) $setting->points_per_currency_unit
        );

        if ($points <= 0) {
            return null;
        }

        return DB::transaction(function () use ($order, $points) {
            $existing = LoyaltyTransaction::query()
                ->where('order_id', $order->id)
                ->where('type', 'earned')
                ->lockForUpdate()
                ->first();

            if ($existing) {
                return $existing;
            }

            $account = CustomerLoyaltyAccount::query()
                ->firstOrCreate(
                    ['customer_id' => $order->customer_id],
                    [
                        'points_balance' => 0,
                        'lifetime_earned' => 0,
                        'lifetime_redeemed' => 0,
                    ]
                );

            $account = CustomerLoyaltyAccount::query()
                ->whereKey($account->id)
                ->lockForUpdate()
                ->firstOrFail();

            $debtPayment = min((int) $account->refund_points_debt, $points);
            $account->refund_points_debt -= $debtPayment;
            $account->points_balance += $points - $debtPayment;
            $account->lifetime_earned += $points;
            $account->save();

            $earned = LoyaltyTransaction::create([
                'customer_loyalty_account_id' => $account->id,
                'customer_id' => $order->customer_id,
                'branch_id' => $order->branch_id,
                'order_id' => $order->id,
                'type' => 'earned',
                'points' => $points,
                'balance_after' => $account->points_balance + $debtPayment,
                'description' => 'Points earned from order #' . $order->id,
            ]);
            if ($debtPayment > 0) LoyaltyTransaction::create([
                'customer_loyalty_account_id' => $account->id, 'customer_id' => $order->customer_id,
                'branch_id' => $order->branch_id, 'order_id' => $order->id, 'type' => 'adjustment',
                'points' => -$debtPayment, 'balance_after' => $account->points_balance,
                'description' => 'Refund points debt repayment',
            ]);
            return $earned;
        });
    }
}