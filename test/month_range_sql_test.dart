// The month boundary as SQL sees it, not as Dart does.
//
// `month_range_test.dart` compares `DateTime`s in Dart. The totals above the lists,
// and the contents of a backup, come from SQL instead: drift stores a `dateTime()`
// column as whole Unix seconds, so the bound handed to `isBetween` is not the bound
// held in Dart — it is that bound floored to the second. Every monthly figure in the
// app rests on those two agreeing.
//
// Nothing used to exercise the SQL side. `export_month_usecase_test.dart` runs against
// a fake repository that applies the same predicate as `MonthRange.contains`, so it
// agreed with itself by construction, and the one test that mentioned the conversion
// performed the truncation itself and then asserted its own arithmetic.
//
// The native library here is the host's, not the app's: `flutter test` runs on the
// Dart VM, where `package:sqlite3` opens `sqlite3.dll` and then `winsqlite3.dll` on
// Windows, or a system `libsqlite3` on Linux. The app ships its own copy through
// `sqlite3_flutter_libs`, which a host test cannot reach, so this is a different
// build of SQLite — and that is fine, because nothing here depends on the build:
// what is pinned is drift's `DateTime` conversion and the inclusivity of `BETWEEN`
// over integers, neither of which is implementation-specific.

import 'package:drift/native.dart';
import 'package:expense_tracker/data/database/app_database.dart';
import 'package:expense_tracker/domain/entities/month_range.dart';
import 'package:flutter_test/flutter_test.dart';

/// What `DynamicLibrary.open` puts in the message when it cannot find a library.
///
/// Only an `ArgumentError` carrying this marker is treated as "this host has no
/// SQLite". Anything else escaping the open — a schema problem, a migration bug — is
/// rethrown, so a broken database cannot turn into a quiet skip.
const String _missingLibraryMarker = 'Failed to load dynamic library';

void main() {
  final MonthRange september = MonthRange.of(DateTime(2026, 9, 15));
  final MonthRange october = MonthRange.of(DateTime(2026, 10, 15));
  final MonthRange november = MonthRange.of(DateTime(2026, 11, 15));

  /// Every instant the boundary is argued about, with the month it belongs to.
  ///
  /// The 1st at midnight and the last day at 23:59:59 name the two ends; the final
  /// microsecond is the value that survives only because the column floors rather
  /// than rounds; the mid-month row carries the time of day the add page used to
  /// write, and its neighbours are the two days the old filter leaked.
  final Map<DateTime, MonthRange> fixtures = <DateTime, MonthRange>{
    DateTime(2026, 9, 30, 23, 59, 59): september,
    DateTime(2026, 10, 1): october,
    DateTime(2026, 10, 15, 14, 30): october,
    DateTime(2026, 10, 31, 23, 59, 59): october,
    DateTime(2026, 10, 31, 23, 59, 59, 999, 999): october,
    DateTime(2026, 11, 1): november,
  };

  /// Writes every fixture through the real companion into [db].
  Future<void> seed(AppDatabase db) async {
    final int categoryId = (await db.getCategories(type: 'expense')).first.id;

    for (final DateTime date in fixtures.keys) {
      await db.insertTransaction(TransactionsCompanion.insert(
        type: 'expense',
        amount: 10,
        categoryId: categoryId,
        date: date,
      ));
    }
  }

  /// Runs [body] against a real in-memory database, skipping loudly when this host
  /// has no SQLite to open.
  ///
  /// The real schema, the real migration and the real category seed: the whole point
  /// is that the query under test is the query the app runs. A host without a loadable
  /// SQLite is reported as skipped rather than failed, because that is an environment
  /// problem and not a statement about this change — but it is reported, not hidden.
  void sqliteTest(
    String description,
    Future<void> Function(AppDatabase db) body,
  ) {
    test(description, () async {
      late final AppDatabase db;
      try {
        db = AppDatabase.withExecutor(NativeDatabase.memory());
      } on ArgumentError catch (error) {
        if (!'${error.message}'.contains(_missingLibraryMarker)) rethrow;
        markTestSkipped('no SQLite for `flutter test` to load on this host '
            '(the app ships its own; host tests use the system one): $error');
        return;
      }

      try {
        await seed(db);
        await body(db);
      } finally {
        await db.close();
      }
    });
  }

  sqliteTest(
    'the list filter keeps every row the SQL range returns',
    (AppDatabase db) async {
      final List<Transaction> rows =
          await db.getTransactionsByDateRange(october.start, october.end);

      expect(rows, isNotEmpty,
          reason: 'the fixture month must return rows at all, or the rest of this '
              'test passes for the wrong reason');

      expect(
        rows
            .where((Transaction row) => october.contains(row.date))
            .map((Transaction row) => row.id)
            .toSet(),
        rows.map((Transaction row) => row.id).toSet(),
        reason: 'the list filter must keep exactly the rows the totals counted',
      );

      // The on-screen lists call the joined wrapper rather than the plain range, so the
      // same set is asserted for it. The predicate there is copy-identical today, which
      // is exactly the kind of thing that drifts apart; and that wrapper joins on the
      // category, so a row the range returns could be dropped on the way to the screen.
      final List<TransactionWithNames> named =
          await db.getTransactionsByDateRangeWithNames(october.start, october.end);

      expect(
        named.map((TransactionWithNames row) => row.transaction.id).toSet(),
        rows.map((Transaction row) => row.id).toSet(),
        reason: 'the wrapper behind the lists must return the same month',
      );
    },
  );

  sqliteTest(
    'three neighbouring months partition the rows exactly',
    (AppDatabase db) async {
      // A row counted in two months is double-counted; a row counted in none vanishes
      // from every total. Both are what a wrong bound produces.
      final List<int> counts = <int>[];

      for (final MonthRange month in <MonthRange>[september, october, november]) {
        final List<Transaction> rows =
            await db.getTransactionsByDateRange(month.start, month.end);
        counts.add(rows.length);
      }

      expect(counts, <int>[1, 4, 1],
          reason: 'September has the neighbour day, October has its own four rows, '
              'November has its 1st');
      expect(counts.fold<int>(0, (int sum, int count) => sum + count),
          fixtures.length);
    },
  );

  sqliteTest(
    'the last second of the month survives the round trip',
    (AppDatabase db) async {
      final List<Transaction> rows =
          await db.getTransactionsByDateRange(october.start, october.end);
      final List<DateTime> stored = rows
          .map((Transaction row) => row.date)
          .toList()
        ..sort();

      // Where the microsecond bound meets whole-second storage: a row written at
      // 23:59:59.999999 comes back as 23:59:59, and the range still counts it. A bound
      // that rounded up, or one that stopped a day early, would drop it from the month.
      expect(stored.last, DateTime(2026, 10, 31, 23, 59, 59));
      expect(october.contains(stored.last), isTrue);
    },
  );

  sqliteTest(
    'the month total equals the rows the list would show',
    (AppDatabase db) async {
      // The symptom being guarded is a list and the total above it disagreeing, so the
      // property is asserted rather than the mechanism.
      final double total =
          await db.getTotalExpense(start: october.start, end: october.end);

      final List<Transaction> rows =
          await db.getTransactionsByDateRange(october.start, october.end);
      final double listed = rows
          .where((Transaction row) => october.contains(row.date))
          .fold<double>(0, (double sum, Transaction row) => sum + row.amount);

      expect(listed, greaterThan(0));
      expect(total, listed,
          reason: 'the summary card must equal the sum of the visible rows');
      expect(total, 40); // four October fixtures at 10 each
    },
  );
}
