class AuditLogUser {
  const AuditLogUser({
    required this.id,
    required this.name,
    required this.email,
  });

  final int id;
  final String name;
  final String email;

  factory AuditLogUser.fromJson(Map<String, dynamic> json) {
    return AuditLogUser(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
    );
  }
}

class AuditLogEntry {
  const AuditLogEntry({
    required this.id,
    required this.userId,
    required this.user,
    required this.action,
    required this.auditableType,
    required this.auditableId,
    required this.oldValues,
    required this.newValues,
    required this.ipAddress,
    required this.createdAt,
  });

  final int id;
  final int? userId;
  final AuditLogUser? user;
  final String action;
  final String? auditableType;
  final int? auditableId;
  final Map<String, dynamic>? oldValues;
  final Map<String, dynamic>? newValues;
  final String? ipAddress;
  final DateTime? createdAt;

  factory AuditLogEntry.fromJson(Map<String, dynamic> json) {
    return AuditLogEntry(
      id: (json['id'] as num).toInt(),
      userId: (json['user_id'] as num?)?.toInt(),
      user: json['user'] is Map<String, dynamic>
          ? AuditLogUser.fromJson(json['user'] as Map<String, dynamic>)
          : null,
      action: json['action'] as String? ?? '',
      auditableType: json['auditable_type'] as String?,
      auditableId: (json['auditable_id'] as num?)?.toInt(),
      oldValues: json['old_values'] is Map
          ? Map<String, dynamic>.from(json['old_values'] as Map)
          : null,
      newValues: json['new_values'] is Map
          ? Map<String, dynamic>.from(json['new_values'] as Map)
          : null,
      ipAddress: json['ip_address'] as String?,
      createdAt: json['created_at'] == null
          ? null
          : DateTime.tryParse(json['created_at'] as String),
    );
  }
}

class AuditLogListPage {
  const AuditLogListPage({
    required this.data,
    required this.currentPage,
    required this.lastPage,
    required this.perPage,
    required this.total,
  });

  final List<AuditLogEntry> data;
  final int currentPage;
  final int lastPage;
  final int perPage;
  final int total;

  factory AuditLogListPage.fromJson(Map<String, dynamic> json) {
    final data = (json['data'] as List<dynamic>? ?? [])
        .map(
          (item) => AuditLogEntry.fromJson(
            item as Map<String, dynamic>,
          ),
        )
        .toList();

    final meta = json['meta'] as Map<String, dynamic>? ?? {};

    return AuditLogListPage(
      data: data,
      currentPage: (meta['current_page'] as num?)?.toInt() ?? 1,
      lastPage: (meta['last_page'] as num?)?.toInt() ?? 1,
      perPage: (meta['per_page'] as num?)?.toInt() ?? 20,
      total: (meta['total'] as num?)?.toInt() ?? data.length,
    );
  }
}