import 'package:flutter/foundation.dart';

@immutable
class StaffBranch {
  const StaffBranch({
    required this.id,
    required this.name,
    required this.code,
    required this.isPrimary,
  });

  final int id;
  final String name;
  final String code;
  final bool isPrimary;

  factory StaffBranch.fromJson(Map<String, dynamic> json) {
    return StaffBranch(
      id: json['id'] as int,
      name: json['name'] as String,
      code: json['code'] as String,
      isPrimary: json['is_primary'] as bool? ?? false,
    );
  }
}

@immutable
class StaffMember {
  const StaffMember({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.isActive,
    required this.roles,
    required this.branches,
  });

  final int id;
  final String name;
  final String email;
  final String? phone;
  final bool isActive;
  final List<String> roles;
  final List<StaffBranch> branches;

  String get primaryRole => roles.isNotEmpty ? roles.first : '';

  StaffBranch? get primaryBranch {
    for (final branch in branches) {
      if (branch.isPrimary) return branch;
    }
    return branches.isNotEmpty ? branches.first : null;
  }

  factory StaffMember.fromJson(Map<String, dynamic> json) {
    return StaffMember(
      id: json['id'] as int,
      name: json['name'] as String,
      email: json['email'] as String,
      phone: json['phone'] as String?,
      isActive: json['is_active'] as bool? ?? false,
      roles: List<String>.from(json['roles'] as List? ?? const []),
      branches: (json['branches'] as List? ?? const [])
          .map((branch) => StaffBranch.fromJson(
                branch as Map<String, dynamic>,
              ))
          .toList(),
    );
  }
}

@immutable
class StaffListPage {
  const StaffListPage({
    required this.data,
    required this.currentPage,
    required this.lastPage,
    required this.perPage,
    required this.total,
  });

  final List<StaffMember> data;
  final int currentPage;
  final int lastPage;
  final int perPage;
  final int total;

  bool get hasNextPage => currentPage < lastPage;

  factory StaffListPage.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as List? ?? const [];
    final meta = json['meta'] as Map<String, dynamic>? ?? const {};

    return StaffListPage(
      data: data
          .map((item) => StaffMember.fromJson(
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
