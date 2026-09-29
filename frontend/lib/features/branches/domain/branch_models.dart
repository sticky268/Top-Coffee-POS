import 'package:flutter/foundation.dart';

@immutable
class Branch {
  const Branch({
    required this.id,
    required this.name,
    required this.code,
    required this.address,
    required this.phone,
    required this.timezone,
    required this.isActive,
    required this.usersCount,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String name;
  final String code;
  final String? address;
  final String? phone;
  final String timezone;
  final bool isActive;
  final int usersCount;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory Branch.fromJson(Map<String, dynamic> json) {
    return Branch(
      id: json['id'] as int,
      name: json['name'] as String,
      code: json['code'] as String,
      address: json['address'] as String?,
      phone: json['phone'] as String?,
      timezone: json['timezone'] as String? ?? 'Asia/Phnom_Penh',
      isActive: json['is_active'] as bool? ?? false,
      usersCount: json['users_count'] as int? ?? 0,
      createdAt: _parseDateTime(json['created_at']),
      updatedAt: _parseDateTime(json['updated_at']),
    );
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value as String);
  }
}

@immutable
class BranchListPage {
  const BranchListPage({
    required this.data,
    required this.currentPage,
    required this.lastPage,
    required this.perPage,
    required this.total,
  });

  final List<Branch> data;
  final int currentPage;
  final int lastPage;
  final int perPage;
  final int total;

  bool get hasNextPage => currentPage < lastPage;

  factory BranchListPage.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as List? ?? const [];
    final meta = json['meta'] as Map<String, dynamic>? ?? const {};

    return BranchListPage(
      data: data
          .map((item) => Branch.fromJson(
                item as Map<String, dynamic>,
              ))
          .toList(),
      currentPage: meta['current_page'] as int? ?? 1,
      lastPage: meta['last_page'] as int? ?? 1,
      perPage: meta['per_page'] as int? ?? 20,
      total: meta['total'] as int? ?? 0,
    );
  }
}