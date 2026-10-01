import 'package:flutter/foundation.dart';

@immutable
class SubscriptionPlan {
  const SubscriptionPlan({
    required this.id,
    required this.name,
    required this.slug,
    required this.branchLimit,
    required this.price,
    required this.billingInterval,
    required this.isActive,
  });

  final int id;
  final String name;
  final String slug;
  final int branchLimit;
  final double price;
  final String billingInterval;
  final bool isActive;

  factory SubscriptionPlan.fromJson(Map<String, dynamic> json) {
    return SubscriptionPlan(
      id: json['id'] as int,
      name: json['name'] as String,
      slug: json['slug'] as String,
      branchLimit: json['branch_limit'] as int,
      price: double.parse(json['price'].toString()),
      billingInterval: json['billing_interval'] as String,
      isActive: json['is_active'] as bool? ?? false,
    );
  }
}

@immutable
class BranchUsage {
  const BranchUsage({
    required this.current,
    required this.limit,
    required this.remaining,
  });

  final int current;
  final int? limit;
  final int? remaining;

  factory BranchUsage.fromJson(Map<String, dynamic> json) {
    return BranchUsage(
      current: json['current'] as int? ?? 0,
      limit: json['limit'] as int?,
      remaining: json['remaining'] as int?,
    );
  }
}

@immutable
class SubscriptionStatus {
  const SubscriptionStatus({
    required this.status,
    required this.startedAt,
    required this.expiresAt,
    required this.isActive,
    required this.isExpired,
    required this.canModify,
  });

  final String status;
  final DateTime? startedAt;
  final DateTime? expiresAt;
  final bool isActive;
  final bool isExpired;
  final bool canModify;

  bool get isTrial => status == 'trial';

  bool get isSuspended => status == 'suspended';

  factory SubscriptionStatus.fromJson(Map<String, dynamic> json) {
    return SubscriptionStatus(
      status: json['status'] as String,
      startedAt: _parseDate(json['started_at']),
      expiresAt: _parseDate(json['expires_at']),
      isActive: json['is_active'] as bool? ?? false,
      isExpired: json['is_expired'] as bool? ?? false,
      canModify: json['can_modify'] as bool? ?? false,
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }
}

@immutable
class SubscriptionDetails {
  const SubscriptionDetails({
    required this.plan,
    required this.branchUsage,
    required this.subscription,
  });

  final SubscriptionPlan? plan;
  final BranchUsage branchUsage;
  final SubscriptionStatus subscription;

  bool get canModify => subscription.canModify;

  bool get isExpired => subscription.isExpired;

  bool get isSuspended => subscription.isSuspended;

  bool get isReadOnly => !subscription.canModify;

  factory SubscriptionDetails.fromJson(Map<String, dynamic> json) {
    return SubscriptionDetails(
      plan: json['plan'] == null
          ? null
          : SubscriptionPlan.fromJson(
              json['plan'] as Map<String, dynamic>,
            ),
      branchUsage: BranchUsage.fromJson(
        json['branch_usage'] as Map<String, dynamic>,
      ),
      subscription: SubscriptionStatus.fromJson(
        json['subscription'] as Map<String, dynamic>,
      ),
    );
  }
}
