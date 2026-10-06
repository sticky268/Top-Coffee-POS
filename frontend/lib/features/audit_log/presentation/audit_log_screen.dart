import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/widgets/app_buttons.dart' as pos_ui;
import '../application/audit_log_list_controller.dart';
import '../application/audit_log_list_state.dart';
import '../domain/audit_log_models.dart';

class AuditLogScreen extends ConsumerStatefulWidget {
  const AuditLogScreen({super.key});

  @override
  ConsumerState<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends ConsumerState<AuditLogScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;

    final position = _scrollController.position;

    if (position.pixels >= position.maxScrollExtent - 300) {
      ref.read(auditLogListControllerProvider.notifier).loadMore();
    }
  }

  Future<void> _search() async {
    await ref
        .read(auditLogListControllerProvider.notifier)
        .applySearch(_searchController.text);
  }

  Future<void> _refresh() async {
    await ref.read(auditLogListControllerProvider.notifier).refresh();
  }

  void _clearSearch() {
    _searchController.clear();
    ref.read(auditLogListControllerProvider.notifier).applySearch('');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(auditLogListControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Audit Log'),
        actions: [
          pos_ui.IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          Expanded(child: _buildBody(state)),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: TextField(
        controller: _searchController,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _search(),
        decoration: InputDecoration(
          hintText: 'Search audit logs...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchController.text.isEmpty
              ? null
              : pos_ui.IconButton(
                  tooltip: 'Clear',
                  onPressed: _clearSearch,
                  icon: const Icon(Icons.clear),
                ),
          border: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
          ),
        ),
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  Widget _buildBody(AuditLogListState state) {
    if (state is AuditLogListLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state is AuditLogListError) {
      return _buildError(state.message);
    }

    if (state is AuditLogListLoaded) {
      if (state.logs.isEmpty) {
        return _buildEmpty();
      }

      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView.separated(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          itemCount: state.logs.length + (state.isLoadingMore ? 1 : 0),
          separatorBuilder: (_, index) {
            if (index >= state.logs.length - 1) {
              return const SizedBox.shrink();
            }

            return const SizedBox(height: 8);
          },
          itemBuilder: (context, index) {
            if (index >= state.logs.length) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              );
            }

            return _AuditLogCard(log: state.logs[index]);
          },
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildError(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            pos_ui.PrimaryButton.icon(
              onPressed: () {
                ref.read(auditLogListControllerProvider.notifier).load();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 120),
          Center(
            child: Column(
              children: [
                Icon(Icons.history_outlined, size: 56),
                SizedBox(height: 16),
                Text('No audit logs found'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AuditLogCard extends StatelessWidget {
  const _AuditLogCard({required this.log});

  final AuditLogEntry log;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(child: Icon(_iconForAction(log.action))),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _formatAction(log.action),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        log.user?.name ?? 'System',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                if (log.createdAt != null)
                  Text(
                    DateFormat('dd MMM, HH:mm')
                        .format(log.createdAt!.toLocal()),
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
            if (log.auditableType != null) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(Icons.link_outlined, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${_shortType(log.auditableType!)}'
                      '${log.auditableId != null ? ' #${log.auditableId}' : ''}',
                    ),
                  ),
                ],
              ),
            ],
            if (log.newValues != null || log.oldValues != null) ...[
              const SizedBox(height: 8),
              Text(_changeSummary(log), style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }

  static IconData _iconForAction(String action) {
    if (action.startsWith('order.')) {
      return Icons.receipt_long_outlined;
    }

    if (action.startsWith('inventory.')) {
      return Icons.inventory_2_outlined;
    }

    if (action.startsWith('user.')) {
      return Icons.person_outline;
    }

    return Icons.history;
  }

  static String _formatAction(String action) {
    return action
        .replaceAll('.', ' ')
        .replaceAll('_', ' ')
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  static String _shortType(String type) {
    if (type.contains('\\')) {
      return type.split('\\').last;
    }

    return type;
  }

  static String _changeSummary(AuditLogEntry log) {
    final oldValues = log.oldValues;
    final newValues = log.newValues;

    if (oldValues == null && newValues == null) {
      return '';
    }

    final values = newValues ?? oldValues ?? {};

    if (values.isEmpty) {
      return '';
    }

    final entries = values.entries
        .take(3)
        .map((entry) => '${entry.key}: ${entry.value}');

    return entries.join(' • ');
  }
}
