import 'package:flutter/material.dart';

/// Maps the real backend order-status enum
/// (held|new|preparing|ready|completed|cancelled — see the orders table
/// migration) to display colors/labels.
///
/// Deliberately NOT reusing dashboard/presentation/widgets/
/// order_status_presentation.dart: that file maps a *different*,
/// dashboard-only mock enum (pending|preparing|ready|completed|cancelled)
/// that doesn't even cover the same value set as the real backend (no
/// "held"/"new"), and importing across features into dashboard's mock
/// domain would be an odd coupling for a real, API-backed feature to
/// depend on. This is a small, independent mapping for the real enum.
Color orderStatusColor(String status, ColorScheme scheme) {
  return switch (status) {
    'held' => Colors.grey,
    'new' => Colors.orange,
    'preparing' => Colors.blue,
    'ready' => Colors.teal,
    'completed' => Colors.green,
    'cancelled' => scheme.error,
    _ => scheme.onSurfaceVariant,
  };
}

String orderStatusLabel(String status) {
  return switch (status) {
    'held' => 'Held',
    'new' => 'New',
    'preparing' => 'Preparing',
    'ready' => 'Ready',
    'completed' => 'Completed',
    'cancelled' => 'Cancelled',
    _ => status,
  };
}

String orderTypeLabel(String orderType) {
  return switch (orderType) {
    'dine_in' => 'Dine-in',
    'takeaway' => 'Takeaway',
    _ => orderType,
  };
}

String paymentMethodLabel(String method) {
  return switch (method) {
    'cash' => 'Cash',
    'card' => 'Card',
    'qr' => 'QR',
    'split' => 'Split',
    _ => method,
  };
}
