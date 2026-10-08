import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../config/env.dart';

import 'tables.dart';

part 'app_database.g.dart';

/// Offline-first local database. This is the source of truth for the POS
/// while offline — not merely a cache the UI falls back to. See Phase 1
/// "Offline Synchronization Architecture".
///
/// NOTE: run `dart run build_runner build` after `flutter pub get` to
/// generate app_database.g.dart — this file will not compile until then.
@DriftDatabase(tables: [CachedProducts, CachedCategories, PendingOrders])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());
  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 1;

  static QueryExecutor _openConnection() {
    return LazyDatabase(() async {
      final dbFolder = await getApplicationDocumentsDirectory();
      final scope = const Uuid().v5(Namespace.url.value, Env.apiBaseUrl);
      final file = File(p.join(dbFolder.path, 'top_coffee_pos_$scope.sqlite'));
      return NativeDatabase.createInBackground(file);
    });
  }
}
