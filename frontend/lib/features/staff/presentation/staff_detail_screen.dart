import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/subscription/subscription_action_guard.dart';
import '../data/staff_repository.dart';
import '../domain/staff_models.dart';
import 'edit_staff_screen.dart';

class StaffDetailScreen extends ConsumerStatefulWidget {
  const StaffDetailScreen({
    super.key,
    required this.staffId,
  });

  final int staffId;

  @override
  ConsumerState<StaffDetailScreen> createState() => _StaffDetailScreenState();
}

class _StaffDetailScreenState extends ConsumerState<StaffDetailScreen> {
  late Future<StaffMember> _staffFuture;

  @override
  void initState() {
    super.initState();
    _loadStaff();
  }

  void _loadStaff() {
    _staffFuture =
        ref.read(staffRepositoryProvider).getStaffMember(widget.staffId);
  }

  @override
  Widget build(BuildContext context) {
    final canModify = SubscriptionActionGuard.canModify(ref);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Staff Profile'),
        actions: [
          IconButton(
            tooltip: canModify ? 'Edit staff' : 'Subscription is read-only',
            icon: const Icon(Icons.edit_outlined),
            onPressed: canModify
                ? () async {
                    final changed = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) =>
                            EditStaffScreen(staffId: widget.staffId),
                      ),
                    );

                    if (changed == true && mounted) {
                      setState(_loadStaff);
                    }
                  }
                : null,
          ),
        ],
      ),
      body: FutureBuilder<StaffMember>(
        future: _staffFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  snapshot.error.toString(),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final staff = snapshot.data;

          if (staff == null) {
            return const Center(
              child: Text('Staff member not found'),
            );
          }

          return _StaffProfile(staff: staff);
        },
      ),
    );
  }
}

class _StaffProfile extends StatelessWidget {
  const _StaffProfile({
    required this.staff,
  });

  final StaffMember staff;

  @override
  Widget build(BuildContext context) {
    final primaryBranch = staff.primaryBranch;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Center(
          child: CircleAvatar(
            radius: 36,
            child: Text(
              staff.name.isEmpty
                  ? '?'
                  : staff.name.substring(0, 1).toUpperCase(),
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(
            staff.name,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            _roleLabel(staff.primaryRole),
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _InfoRow(
                  label: 'Email',
                  value: staff.email,
                ),
                if (staff.phone != null && staff.phone!.isNotEmpty)
                  _InfoRow(
                    label: 'Phone',
                    value: staff.phone!,
                  ),
                _InfoRow(
                  label: 'Status',
                  value: staff.isActive ? 'Active' : 'Inactive',
                ),
                if (primaryBranch != null)
                  _InfoRow(
                    label: 'Primary Branch',
                    value: '${primaryBranch.name} · ${primaryBranch.code}',
                  ),
              ],
            ),
          ),
        ),
        if (staff.branches.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            'Branches',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                for (final branch in staff.branches)
                  ListTile(
                    title: Text(branch.name),
                    subtitle: Text(branch.code),
                    trailing: branch.isPrimary
                        ? const Chip(
                            label: Text('Primary'),
                          )
                        : null,
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'kitchen_staff':
        return 'Kitchen Staff';
      case 'admin':
        return 'Admin';
      case 'manager':
        return 'Manager';
      case 'cashier':
        return 'Cashier';
      default:
        return role.isEmpty ? 'No role' : role;
    }
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }
}
