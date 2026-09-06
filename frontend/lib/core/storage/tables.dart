import 'package:drift/drift.dart';

/// Local cache of branch-scoped products, for offline browsing.
/// Mirrors a subset of the server `products` table.
class CachedProducts extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text()();
  IntColumn get categoryId => integer()();
  RealColumn get basePrice => real()();
  BoolColumn get isAvailable => boolean().withDefault(const Constant(true))();
  TextColumn get dataJson => text()(); // full server payload for anything the UI needs beyond the cached columns

  @override
  Set<Column> get primaryKey => {id};
}

class CachedCategories extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Orders created while offline (or online — the app always writes here
/// first, then syncs). `syncStatus` drives the background sync worker.
class PendingOrders extends Table {
  TextColumn get uuid => text()(); // client-generated idempotency key
  TextColumn get payloadJson => text()(); // full order payload matching the API's order-create shape
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))(); // pending | synced | failed | conflict
  IntColumn get attemptCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get lastAttemptAt => dateTime().nullable()();
  TextColumn get lastError => text().nullable()();

  @override
  Set<Column> get primaryKey => {uuid};
}
