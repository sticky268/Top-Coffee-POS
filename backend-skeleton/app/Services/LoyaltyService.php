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

            $account->points_balance += $points;
            $account->lifetime_earned += $points;
            $account->save();

            return LoyaltyTransaction::create([
                'customer_loyalty_account_id' => $account->id,
                'customer_id' => $order->customer_id,
                'branch_id' => $order->branch_id,
                'order_id' => $order->id,
                'type' => 'earned',
                'points' => $points,
                'balance_after' => $account->points_balance,
                'description' => 'Points earned from order #' . $order->id,
            ]);
        });
    }
}