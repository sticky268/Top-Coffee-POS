import 'dart:async';
import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../offline/local_store.dart';

typedef DrawerScope = ({int userId, int branchId});

/// Device-reported command evidence. There is no drawer-open sensor.
class CashDrawerEvent {
  const CashDrawerEvent({
    required this.id,
    required this.scope,
    required this.source,
    required this.reason,
    required this.requestedAt,
    this.orderId,
    this.status = 'attempt_recorded',
    this.finishedAt,
  });

  final String id, source, reason, status;
  final DrawerScope scope;
  final int? orderId;
  final DateTime requestedAt;
  final DateTime? finishedAt;

  Map<String, dynamic> toJson() => {
    'event_uuid': id,
    'expected_user_id': scope.userId,
    'branch_id': scope.branchId,
    'source': source,
    if (orderId != null) 'order_id': orderId,
    'reason': reason,
    'status': status,
    'device_requested_at': requestedAt.toUtc().toIso8601String(),
    if (finishedAt != null)
      'device_finished_at': finishedAt!.toUtc().toIso8601String(),
  };

  factory CashDrawerEvent.fromJson(Map<String, dynamic> json) => CashDrawerEvent(
    id: json['event_uuid'] as String,
    scope: (
      userId: json['expected_user_id'] as int,
      branchId: json['branch_id'] as int,
    ),
    source: json['source'] as String,
    reason: json['reason'] as String,
    orderId: json['order_id'] as int?,
    requestedAt: DateTime.parse(json['device_requested_at'] as String),
    status: json['status'] as String,
    finishedAt: json['device_finished_at'] == null ? null
        : DateTime.parse(json['device_finished_at'] as String),
  );

  CashDrawerEvent finish(String outcome) => CashDrawerEvent(
    id: id, scope: scope, source: source, reason: reason, orderId: orderId,
    requestedAt: requestedAt, status: outcome, finishedAt: DateTime.now().toUtc(),
  );
}

/// A permanent upload rejection is reviewable and must not block other records.
class CashDrawerUploadRejected implements Exception {
  const CashDrawerUploadRejected(this.message);
  final String message;
}

class CashDrawerUploadReview {
  const CashDrawerUploadReview(this.message, this.recordedAt);
  final String message;
  final DateTime recordedAt;
  Map<String, dynamic> toJson() => {
    'message': message, 'recorded_at': recordedAt.toUtc().toIso8601String(),
  };
  factory CashDrawerUploadReview.fromJson(Map<String, dynamic> json) =>
      CashDrawerUploadReview(json['message'] as String,
        DateTime.parse(json['recorded_at'] as String));
}

class CashDrawerActivity {
  const CashDrawerActivity(this.event, this.uploaded, this.review);
  final CashDrawerEvent event;
  final bool uploaded;
  final CashDrawerUploadReview? review;
}

/// Separate from payment and print queues. Uploads never send hardware commands.
/// The durable initial event is required before a drawer command is attempted.
class CashDrawerJournal {
  CashDrawerJournal(this.store, {String Function()? newId})
      : _newId = newId ?? const Uuid().v4;
  final LocalStore store;
  final String Function() _newId;
  final _changes = StreamController<void>.broadcast();
  Stream<void> get changes => _changes.stream;
  String _prefix(DrawerScope scope) =>
      'drawer-event:${scope.userId}:${scope.branchId}:';
  String _key(CashDrawerEvent event) => '${_prefix(event.scope)}${event.id}';
  String _ackKey(CashDrawerEvent event) =>
      'drawer-event-ack:${event.scope.userId}:${event.scope.branchId}:${event.id}';

  Future<CashDrawerEvent> begin(
    DrawerScope scope, {int? orderId, String? reason}
  ) async {
    final note = orderId == null ? reason?.trim() ?? '' : 'Completed cash sale';
    if (note.length < 3 || note.length > 255) {
      throw StateError('Enter a reason between 3 and 255 characters.');
    }
    final event = CashDrawerEvent(
      id: _newId(), scope: scope, source: orderId == null ? 'manual' : 'cash_sale',
      orderId: orderId, reason: note, requestedAt: DateTime.now().toUtc(),
    );
    await save(event);
    return event;
  }

  Future<void> save(CashDrawerEvent event) async {
    await store.write(_key(event), jsonEncode(event.toJson()));
    if (!_changes.isClosed) _changes.add(null);
  }

  Future<List<CashDrawerEvent>> list(DrawerScope selected) async {
    final entries = await store.entries(_prefix(selected));
    final events = entries.values.map((raw) => CashDrawerEvent.fromJson(
      Map<String, dynamic>.from(jsonDecode(raw) as Map),
    )).where((event) => event.scope == selected).toList();
    events.sort((a, b) => a.requestedAt.compareTo(b.requestedAt));
    return events;
  }

  String _reviewKey(CashDrawerEvent event) =>
      'drawer-event-review:${event.scope.userId}:${event.scope.branchId}:${event.id}';

  Future<List<CashDrawerActivity>> activity(DrawerScope selected) async {
    final result = <CashDrawerActivity>[];
    for (final event in await list(selected)) {
      final review = await store.read(_reviewKey(event));
      result.add(CashDrawerActivity(
        event, await store.read(_ackKey(event)) == event.status,
        review == null ? null : CashDrawerUploadReview.fromJson(
          Map<String, dynamic>.from(jsonDecode(review) as Map)),
      ));
    }
    return result;
  }

  Future<List<CashDrawerEvent>> pending(DrawerScope selected) async =>
      (await activity(selected)).where((item) =>
        !item.uploaded && item.review == null).map((item) => item.event).toList();

  Future<void> flagForReview(CashDrawerEvent event, String message) async {
    await store.write(_reviewKey(event), jsonEncode(
      CashDrawerUploadReview(message, DateTime.now().toUtc()).toJson(),
    ));
    _notify();
  }

  Future<void> retryUpload(String id, DrawerScope selected) async {
    final matches = (await list(selected)).where((event) => event.id == id);
    if (matches.isEmpty) {
      throw StateError('This drawer record is unavailable for this cashier and branch.');
    }
    await store.delete(_reviewKey(matches.single));
    _notify();
  }

  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }

  // A separate acknowledgement cannot overwrite a newer command outcome.
  Future<void> acknowledge(CashDrawerEvent uploaded) async {
    await store.write(_ackKey(uploaded), uploaded.status);
    _notify();
  }

  void dispose() => unawaited(_changes.close());
}

/// Retries telemetry only while the original signed-in account/branch is active.
/// Failure is retained locally and cannot fail a payment or replay a drawer pulse.
class CashDrawerSync {
  CashDrawerSync(this.journal, this.scope, this.upload);
  final CashDrawerJournal journal;
  final DrawerScope? Function() scope;
  final Future<void> Function(CashDrawerEvent event) upload;
  Future<void>? _running;
  final _clock = Stopwatch();
  Duration _delay = Duration.zero;
  int _failures = 0;

  Future<void> sync({bool force = false}) {
    if (!force && _clock.isRunning && _clock.elapsed < _delay) {
      return Future.value();
    }
    return _running ??= _sync().whenComplete(() => _running = null);
  }

  Future<void> _sync() async {
    final selected = scope();
    if (selected == null) return;
    try {
      for (final event in await journal.pending(selected)) {
        if (scope() != selected) return;
        try {
          await upload(event);
        } on CashDrawerUploadRejected catch (error) {
          await journal.flagForReview(event, error.message);
          continue; // A rejected record cannot block unrelated valid evidence.
        }
        // Acknowledgement belongs to this event's actor, even if sign-out occurs
        // during the request. It never writes any new account's journal.
        await journal.acknowledge(event);
      }
      _failures = 0;
      _delay = Duration.zero;
      _clock.stop();
    } catch (_) {
      _failures = (_failures + 1).clamp(1, 5);
      _delay = Duration(seconds: 15 * (1 << _failures));
      _clock..reset()..start();
    }
  }
}
