import 'package:flutter/material.dart';

import '../../domain/dashboard_models.dart';

/// Presentation-only mapping — kept out of domain/dashboard_models.dart so
/// that file stays framework-agnostic (no Flutter imports), same
/// convention as features/auth/domain.
extension OrderStatusPresentation on OrderStatus {
  String get label => switch (this) {
        OrderStatus.pending => 'Pending',
        OrderStatus.preparing => 'Preparing',
        OrderStatus.ready => 'Ready',
        OrderStatus.completed => 'Completed',
        OrderStatus.cancelled => 'Cancelled',
      };

  Color color(ColorScheme scheme) => switch (this) {
        OrderStatus.pending => Colors.orange,
        OrderStatus.preparing => Colors.blue,
        OrderStatus.ready => Colors.teal,
        OrderStatus.completed => Colors.green,
        OrderStatus.cancelled => scheme.error,
      };

  IconData get icon => switch (this) {
        OrderStatus.pending => Icons.schedule,
        OrderStatus.preparing => Icons.local_fire_department_outlined,
        OrderStatus.ready => Icons.notifications_active_outlined,
        OrderStatus.completed => Icons.check_circle_outline,
        OrderStatus.cancelled => Icons.cancel_outlined,
      };
}
