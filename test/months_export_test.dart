// Which months "export every month" walks, and what each one produces.
//
// The page loops over this list and uploads one file per entry, so the list has
// to be exactly the months that hold a transaction: a month that is missing from
// it is a month the user never gets a backup of, and a month that is in it twice
// is an upload done twice.

import 'package:drift/drift.dart' show Value;
import 'package:expense_tracker/data/database/app_database.dart';
import 'package:expense_tracker/data/repositories/transaction_repository_impl.dart';
import 'package:expense_tracker/domain/usecases/export_month_usecase.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sqlite_support.dart';

Future<void> _insert(AppDatabase db, DateTime date) async {
  final int categoryId = (await db.getCategories(type: 'expense')).first.id;
  final Subcategory food = (await db.getSubcategories(categoryId))
      .firstWhere((Subcategory s) => s.name == 'Food');
  await db.insertTransaction(TransactionsCompanion.insert(
    type: 'expense',
    amount: 250000,
    categoryId: categoryId,
    subcategoryId: Value(food.id),
    date: date,
    createdAt: Value(date),
  ));
}

void main() {
  sqliteTest('a database with nothing in it offers no months',
      (AppDatabase db) async {
    expect(await db.getMonthsWithTransactions(), isEmpty);
  });

  sqliteTest('lists each month once, oldest first, across a year boundary',
      (AppDatabase db) async {
    // Inserted out of order and twice in one month: the list is a set of months,
    // sorted, whatever order the rows arrived in.
    await _insert(db, DateTime(2026, 1, 20));
    await _insert(db, DateTime(2025, 12, 31, 22, 15));
    await _insert(db, DateTime(2026, 1, 3));

    expect(
      await db.getMonthsWithTransactions(),
      <DateTime>[DateTime(2025, 12), DateTime(2026, 1)],
      reason:
          'December 2025 comes before January 2026, and January appears once',
    );
  });

  sqliteTest('each month it lists exports as its own named file',
      (AppDatabase db) async {
    await _insert(db, DateTime(2026, 1, 20));
    await _insert(db, DateTime(2026, 3, 2));

    final ExportMonthUseCase export =
        ExportMonthUseCase(TransactionRepositoryImpl(db));
    final List<DateTime> months = await export.monthsWithTransactions();

    final List<String> files = <String>[
      for (final DateTime month in months) (await export.call(month)).fileName,
    ];

    expect(files, <String>[
      'expense-tracker-2026-01.json',
      'expense-tracker-2026-03.json',
    ]);
  });
}
