import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
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
    OrderStatus.pending => AppColors.forScheme(scheme, AppColors.warning),
    OrderStatus.preparing => AppColors.forScheme(scheme, AppColors.info),
    OrderStatus.ready => AppColors.forScheme(scheme, AppColors.ready),
    OrderStatus.completed => AppColors.forScheme(scheme, AppColors.success),
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
