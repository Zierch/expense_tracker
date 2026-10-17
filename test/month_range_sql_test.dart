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
// The database these queries run against — and the skip on a host with no SQLite to
// open — comes from `sqlite_support.dart`, which every database test shares.

import 'package:expense_tracker/data/database/app_database.dart';
import 'package:expense_tracker/domain/entities/month_range.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sqlite_support.dart';

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

  /// Seeds the fixtures above, then hands the database to the shared harness: the real
  /// schema, the real migration and the real category seed, because the whole point is
  /// that the query under test is the query the app runs.
  void seededSqliteTest(
    String description,
    Future<void> Function(AppDatabase db) body,
  ) {
    sqliteTest(description, (AppDatabase db) async {
      await seed(db);
      await body(db);
    });
  }

  seededSqliteTest(
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

  seededSqliteTest(
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

  seededSqliteTest(
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

  seededSqliteTest(
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
