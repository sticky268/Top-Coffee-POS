import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../offline/local_store.dart';
import 'printer_service.dart';

typedef PrintScope = ({int userId, int branchId});

enum PrintStatus { waiting, sending, sent, failed, uncertain, cancelled }

class PrintJob {
  const PrintJob({
    required this.id,
    required this.userId,
    required this.branchId,
    required this.documentId,
    required this.fingerprint,
    required this.reference,
    required this.payload,
    required this.createdAt,
    this.branchCode,
    this.branchName,
    this.status = PrintStatus.waiting,
    this.attempts = 0,
    this.isCopy = false,
    this.sourceId,
    this.printerIp,
    this.error,
    this.paperConfirmed = false,
  });
  final String id;
  final int userId, branchId;
  final String documentId, fingerprint, reference;
  final String? branchCode, branchName, sourceId, printerIp, error;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final PrintStatus status;
  final int attempts;
  final bool isCopy, paperConfirmed;
  PrintScope get scope => (userId: userId, branchId: branchId);
  bool get pending =>
      status == PrintStatus.waiting ||
      status == PrintStatus.sending ||
      status == PrintStatus.failed ||
      status == PrintStatus.uncertain;

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'branch_id': branchId,
    'document_id': documentId,
    'fingerprint': fingerprint,
    'reference': reference,
    'branch_code': branchCode,
    'branch_name': branchName,
    'source_id': sourceId,
    'printer_ip': printerIp,
    'error': error,
    'payload': payload,
    'created_at': createdAt.toUtc().toIso8601String(),
    'status': status.name,
    'attempts': attempts,
    'is_copy': isCopy,
    'paper_confirmed': paperConfirmed,
  };
  factory PrintJob.fromJson(Map<String, dynamic> json) => PrintJob(
    id: json['id'] as String,
    userId: json['user_id'] as int,
    branchId: json['branch_id'] as int,
    documentId: json['document_id'] as String,
    fingerprint: json['fingerprint'] as String,
    reference: json['reference'] as String,
    payload: Map<String, dynamic>.from(json['payload'] as Map),
    createdAt: DateTime.parse(json['created_at'] as String),
    status: PrintStatus.values.byName(json['status'] as String),
    attempts: json['attempts'] as int,
    isCopy: json['is_copy'] as bool,
    branchCode: json['branch_code'] as String?,
    branchName: json['branch_name'] as String?,
    sourceId: json['source_id'] as String?,
    printerIp: json['printer_ip'] as String?,
    error: json['error'] as String?,
    paperConfirmed: json['paper_confirmed'] == true,
  );
  PrintJob change(Map<String, dynamic> values) =>
      PrintJob.fromJson({...toJson(), ...values});
}

/// A device-local journal, never a payment queue. Acknowledged and uncertain
/// attempts are never automatically replayed; only never-attempted waiting jobs
/// resume automatically. Paper output cannot be proved by the printer SDK.
class PrintQueue {
  PrintQueue(
    this.store,
    this.printer,
    this.scope,
    this.destination, {
    String Function()? newId,
  }) : _newId = newId ?? const Uuid().v4;
  final LocalStore store;
  final PrinterService printer;
  final PrintScope? Function() scope;
  final Future<String> Function(PrintJob job) destination;
  final String Function() _newId;
  final _changes = StreamController<void>.broadcast();
  Stream<void> get changes => _changes.stream;
  Future<void> _tail = Future.value();
  Future<void>? _ready;
  String _prefix(PrintScope s) => 'print:${s.userId}:${s.branchId}:';
  String _key(PrintJob job) => '${_prefix(job.scope)}${job.id}';
  String _assetKey(PrintScope selected, String id) =>
      'print-asset:${selected.userId}:${selected.branchId}:$id';

  Future<void> _initialize() => _ready ??= _recover();
  Future<void> _recover() async {
    for (final entry in (await store.entries('print:')).values) {
      final job = PrintJob.fromJson(
        Map<String, dynamic>.from(jsonDecode(entry) as Map),
      );
      if (job.status == PrintStatus.sending) {
        await _save(
          job.change({
            'status': PrintStatus.uncertain.name,
            'error':
                'Printing was interrupted. Check the paper before making a COPY.',
          }),
        );
      }
    }
  }

  Future<T> _serialized<T>(Future<T> Function() action) {
    final next = _tail.then((_) async {
      await _initialize();
      return action();
    });
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  void _guard(PrintScope selected) {
    if (scope() != selected) {
      throw StateError('Sign in and select this job’s branch.');
    }
  }

  Future<void> _save(PrintJob job) async {
    await store.write(_key(job), jsonEncode(job.toJson()));
    if (!_changes.isClosed) _changes.add(null);
  }

  Future<List<PrintJob>> _list(PrintScope selected) async {
    final entries = await store.entries(_prefix(selected));
    final jobs = entries.values
        .map(
          (v) => PrintJob.fromJson(
            Map<String, dynamic>.from(jsonDecode(v) as Map),
          ),
        )
        .toList();
    jobs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return jobs;
  }

  Future<List<PrintJob>> list(PrintScope selected) async {
    await _initialize();
    _guard(selected);
    return _list(selected);
  }

  Future<PrintJob> _read(String id, PrintScope selected) async {
    _guard(selected);
    final raw = await store.read('${_prefix(selected)}$id');
    if (raw == null) {
      throw StateError('Print job is unavailable for this account and branch.');
    }
    final job = PrintJob.fromJson(
      Map<String, dynamic>.from(jsonDecode(raw) as Map),
    );
    if (job.scope != selected) throw StateError('Print job scope is invalid.');
    return job;
  }

  Future<PrintJob> enqueue({
    required PrintScope selected,
    required String documentId,
    required String reference,
    required Map<String, dynamic> payload,
    String? branchCode,
    String? branchName,
    bool asCopy = false,
  }) => _serialized(() async {
    _guard(selected);
    // Native byte buffers are persisted as base64 and restored only on send.
    final saved = Map<String, dynamic>.from(payload);
    if (saved['logoBytes'] != null) {
      final encoded = base64Encode(List<int>.from(saved['logoBytes'] as List));
      final assetId = const Uuid().v5(Namespace.url.value, encoded);
      final key = _assetKey(selected, assetId);
      if (await store.read(key) == null) await store.write(key, encoded);
      saved['logoBytes'] = '@asset:$assetId';
    }
    final snapshot = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(saved)) as Map,
    );
    if (asCopy) snapshot['documentTitle'] = _copyTitle(snapshot);
    final fingerprint = const Uuid().v5(
      Namespace.url.value,
      jsonEncode([documentId, snapshot]),
    );
    final history = await _list(selected);
    for (final job in history) {
      if (job.fingerprint == fingerprint &&
          job.status != PrintStatus.cancelled &&
          !(asCopy && job.status == PrintStatus.sent)) {
        return job; // Repeated taps cannot create duplicate original jobs.
      }
    }
    final priorAttempt = history.any(
      (j) =>
          j.documentId == documentId &&
          (j.status == PrintStatus.sent ||
              j.status == PrintStatus.uncertain ||
              (j.status == PrintStatus.cancelled && j.attempts > 0)),
    );
    if (asCopy || priorAttempt) {
      snapshot['documentTitle'] = _copyTitle(snapshot);
    }
    final job = PrintJob(
      id: _newId(),
      userId: selected.userId,
      branchId: selected.branchId,
      documentId: documentId,
      fingerprint: fingerprint,
      reference: reference,
      payload: snapshot,
      branchCode: branchCode,
      branchName: branchName,
      createdAt: DateTime.now().toUtc(),
      isCopy: asCopy || priorAttempt,
    );
    _guard(selected);
    await _save(job); // Persist before any printer connection or transmission.
    return job;
  });

  String _copyTitle(Map<String, dynamic> payload) {
    final title = (payload['documentTitle'] as String? ?? '').trim();
    return title.contains('COPY')
        ? title
        : title.isEmpty
        ? 'COPY'
        : 'COPY · $title';
  }

  Future<PrintJob> send(
    String id,
    PrintScope selected,
  ) => _serialized(() async {
    var job = await _read(id, selected);
    if (job.status != PrintStatus.waiting && job.status != PrintStatus.failed) {
      return job;
    }
    if (!job.isCopy &&
        (await _list(selected)).any(
          (other) =>
              other.id != job.id &&
              other.documentId == job.documentId &&
              (other.status == PrintStatus.sent ||
                  other.status == PrintStatus.uncertain),
        )) {
      job = job.change({
        'status': PrintStatus.uncertain.name,
        'error':
            'Another version of this document had a send attempt. Check paper and use Reprint COPY.',
      });
      await _save(job);
      return job;
    }
    var invoked = false;
    try {
      final ip = (await destination(job)).trim();
      if (ip.isEmpty) {
        throw StateError(
          'Configure and enable this branch’s printer, then retry.',
        );
      }
      _guard(selected);
      job = job.change({
        'status': PrintStatus.sending.name,
        'printer_ip': ip,
        'attempts': job.attempts + 1,
        'error': null,
      });
      await _save(job);
      await printer.connect(ip);
      _guard(selected);
      final payload = Map<String, dynamic>.from(job.payload);
      if (payload['logoBytes'] != null) {
        var encoded = payload['logoBytes'] as String;
        if (encoded.startsWith('@asset:')) {
          final saved = await store.read(
            _assetKey(selected, encoded.substring(7)),
          );
          if (saved == null) {
            throw StateError('Saved receipt logo is unavailable.');
          }
          encoded = saved;
        }
        payload['logoBytes'] = Uint8List.fromList(base64Decode(encoded));
      }
      _guard(selected);
      invoked = true;
      await printer.sendPayload(payload);
      job = job.change({'status': PrintStatus.sent.name, 'error': null});
    } catch (error) {
      job = job.change({
        'status': (invoked ? PrintStatus.uncertain : PrintStatus.failed).name,
        'error': invoked
            ? 'Printer confirmation was lost. Check the paper before making a COPY.'
            : error.toString(),
      });
    } finally {
      try {
        await printer.disconnect();
      } catch (_) {
        /* Preserve the send result. */
      }
    }
    // If this write fails after a send, the durable 'sending' job becomes
    // uncertain on restart. It is never silently sent a second time.
    await _save(job);
    return job;
  });

  /// An immediate manual command, never persisted or automatically replayed.
  /// Uses the receipt serializer so connect/disconnect cannot interrupt a print.
  Future<void> openCashDrawer(
    PrintScope selected,
    Future<String> Function() destination,
    void Function() authorize, {
    int? completedSaleId,
  }) => _serialized(() async {
    _guard(selected);
    authorize();
    if (completedSaleId != null) {
      final key = 'cash-drawer:${selected.userId}:${selected.branchId}:order:$completedSaleId';
      if (await store.read(key) != null) return;
      _guard(selected);
      authorize();
      // Consume the automatic attempt before any connection or pulse. A crash,
      // timeout or failure requires an explicit manual action, never a replay.
      await store.write(key, DateTime.now().toUtc().toIso8601String());
    }
    final ip = (await destination()).trim();
    if (ip.isEmpty) throw StateError('Configure this branch’s printer in Receipt Settings.');
    _guard(selected);
    authorize();
    try {
      await printer.connect(ip);
      _guard(selected);
      authorize();
      await printer.openCashDrawer();
    } finally {
      try {
        await printer.disconnect();
      } catch (_) {
        // Disconnect must not hide the command result or trigger a second pulse.
      }
    }
  });

  Future<void> resumeWaiting(PrintScope selected) async {
    for (final job in await list(selected)) {
      if (scope() != selected) return;
      if (job.status == PrintStatus.waiting) await send(job.id, selected);
    }
  }

  Future<PrintJob> copy(String id, PrintScope selected) =>
      _serialized(() async {
        final original = await _read(id, selected);
        if (original.status != PrintStatus.sent &&
            original.status != PrintStatus.uncertain) {
          throw StateError(
            'Retry a failed job; copies require a sent or uncertain job.',
          );
        }
        for (final existing in await _list(selected)) {
          if (existing.sourceId == original.id && existing.pending) {
            return existing;
          }
        }
        final job = PrintJob(
          id: _newId(),
          userId: selected.userId,
          branchId: selected.branchId,
          documentId: original.documentId,
          fingerprint: original.fingerprint,
          reference: original.reference,
          payload: {
            ...original.payload,
            'documentTitle': _copyTitle(original.payload),
          },
          branchCode: original.branchCode,
          branchName: original.branchName,
          createdAt: DateTime.now().toUtc(),
          sourceId: original.id,
          isCopy: true,
        );
        await _save(job);
        return job;
      });
  Future<void> confirmPaper(String id, PrintScope selected) =>
      _serialized(() async {
        final job = await _read(id, selected);
        if (job.status != PrintStatus.sent &&
            job.status != PrintStatus.uncertain) {
          throw StateError('Only an attempted print can be confirmed.');
        }
        await _save(
          job.change({
            'status': PrintStatus.sent.name,
            'paper_confirmed': true,
            'error': null,
          }),
        );
      });
  Future<void> cancel(String id, PrintScope selected) => _serialized(() async {
    final job = await _read(id, selected);
    if (job.status == PrintStatus.sending || job.status == PrintStatus.sent) {
      throw StateError('A sent job cannot be cancelled.');
    }
    await _save(job.change({'status': PrintStatus.cancelled.name}));
  });
  void dispose() => unawaited(_changes.close());
}
