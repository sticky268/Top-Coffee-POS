import '../../customers/domain/customer_models.dart';

class LoyaltyAccount {
  const LoyaltyAccount({
    required this.id,
    required this.customerId,
    required this.pointsBalance,
    required this.lifetimeEarned,
    required this.lifetimeRedeemed,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final int customerId;
  final int pointsBalance;
  final int lifetimeEarned;
  final int lifetimeRedeemed;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory LoyaltyAccount.fromJson(Map<String, dynamic> json) {
    return LoyaltyAccount(
      id: json['id'] as int,
      customerId: json['customer_id'] as int,
      pointsBalance: (json['points_balance'] as num?)?.toInt() ?? 0,
      lifetimeEarned: (json['lifetime_earned'] as num?)?.toInt() ?? 0,
      lifetimeRedeemed: (json['lifetime_redeemed'] as num?)?.toInt() ?? 0,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())
          : null,
    );
  }
}

class LoyaltyBranch {
  const LoyaltyBranch({
    required this.id,
    required this.name,
  });

  final int id;
  final String name;

  factory LoyaltyBranch.fromJson(Map<String, dynamic> json) {
    return LoyaltyBranch(
      id: json['id'] as int,
      name: json['name'] as String,
    );
  }
}

class LoyaltyOrder {
  const LoyaltyOrder({
    required this.id,
    required this.uuid,
  });

  final int id;
  final String uuid;

  factory LoyaltyOrder.fromJson(Map<String, dynamic> json) {
    return LoyaltyOrder(
      id: json['id'] as int,
      uuid: json['uuid'] as String,
    );
  }
}

class LoyaltyTransaction {
  const LoyaltyTransaction({
    required this.id,
    required this.customerLoyaltyAccountId,
    required this.customerId,
    required this.branchId,
    required this.orderId,
    required this.type,
    required this.points,
    required this.balanceAfter,
    required this.description,
    this.branch,
    this.order,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final int customerLoyaltyAccountId;
  final int customerId;
  final int? branchId;
  final int? orderId;
  final String type;
  final int points;
  final int balanceAfter;
  final String? description;
  final LoyaltyBranch? branch;
  final LoyaltyOrder? order;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory LoyaltyTransaction.fromJson(Map<String, dynamic> json) {
    final branchJson = json['branch'];
    final orderJson = json['order'];

    return LoyaltyTransaction(
      id: json['id'] as int,
      customerLoyaltyAccountId:
          json['customer_loyalty_account_id'] as int,
      customerId: json['customer_id'] as int,
      branchId: json['branch_id'] as int?,
      orderId: json['order_id'] as int?,
      type: json['type'] as String,
      points: (json['points'] as num?)?.toInt() ?? 0,
      balanceAfter: (json['balance_after'] as num?)?.toInt() ?? 0,
      description: json['description'] as String?,
      branch: branchJson is Map<String, dynamic>
          ? LoyaltyBranch.fromJson(branchJson)
          : null,
      order: orderJson is Map<String, dynamic>
          ? LoyaltyOrder.fromJson(orderJson)
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())
          : null,
    );
  }
}

class CustomerLoyalty {
  const CustomerLoyalty({
    required this.customer,
    required this.account,
    required this.transactions,
    required this.currentPage,
    required this.lastPage,
    required this.perPage,
    required this.total,
  });

  final Customer customer;
  final LoyaltyAccount account;
  final List<LoyaltyTransaction> transactions;
  final int currentPage;
  final int lastPage;
  final int perPage;
  final int total;

  factory CustomerLoyalty.fromJson(Map<String, dynamic> json) {
    final transactionsJson = json['transactions'] as List<dynamic>? ?? [];
    final meta = json['meta'] as Map<String, dynamic>;

    return CustomerLoyalty(
      customer: Customer.fromJson(json['customer'] as Map<String, dynamic>),
      account: LoyaltyAccount.fromJson(
        json['account'] as Map<String, dynamic>,
      ),
      transactions: transactionsJson
          .map(
            (item) => LoyaltyTransaction.fromJson(
              item as Map<String, dynamic>,
            ),
          )
          .toList(),
      currentPage: meta['current_page'] as int,
      lastPage: meta['last_page'] as int,
      perPage: meta['per_page'] as int,
      total: meta['total'] as int,
    );
  }
}
class LoyaltySettings {
  const LoyaltySettings({
    required this.branchId,
    required this.isEnabled,
    required this.pointsPerCurrencyUnit,
    required this.pointsPerRewardCurrencyUnit,
    required this.minimumRedeemPoints,
    required this.redemptionEnabled,
    required this.expirationMonths,
  });

  final int? branchId;
  final bool isEnabled;
  final double pointsPerCurrencyUnit;
  final double pointsPerRewardCurrencyUnit;
  final int minimumRedeemPoints;
  final bool redemptionEnabled;
  final int? expirationMonths;

  factory LoyaltySettings.fromJson(Map<String, dynamic> json) {
    return LoyaltySettings(
      branchId: json['branch_id'] as int?,
      isEnabled: json['is_enabled'] as bool? ?? false,
      pointsPerCurrencyUnit: double.tryParse(
            json['points_per_currency_unit']?.toString() ?? '0',
          ) ??
          0,
      pointsPerRewardCurrencyUnit: double.tryParse(
            json['points_per_reward_currency_unit']?.toString() ?? '0',
          ) ??
          0,
      minimumRedeemPoints:
          (json['minimum_redeem_points'] as num?)?.toInt() ?? 0,
      redemptionEnabled: json['redemption_enabled'] as bool? ?? false,
      expirationMonths: (json['expiration_months'] as num?)?.toInt(),
    );
  }
}