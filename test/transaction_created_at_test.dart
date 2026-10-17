// A creation time is written once and has to survive every later edit.
//
// The column is stamped by its client default at insert, and a client default applies to
// inserts only: an update whose companion leaves `createdAt` out leaves the stored value
// alone. It travels in a backup, so a wrong value there would be handed back to the user
// as a fact.
//
// The page used to be the half that got this wrong — it built its entity with
// `DateTime.now()` instead of the loaded row's value — and that is asserted through the
// page itself in `edit_transaction_page_test.dart`. What is pinned here is the storage
// contract both halves rest on: a stored creation time comes back unchanged, and an edit
// still writes everything it was given.

import 'package:drift/drift.dart' show Value;
import 'package:expense_tracker/data/database/app_database.dart';
import 'package:expense_tracker/data/repositories/transaction_repository_impl.dart';
import 'package:expense_tracker/domain/entities/transaction_entity.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sqlite_support.dart';

void main() {
  // Fixed, and years away from the clock the test runs on. Left to the clock, the insert
  // and the edit that follows it usually land in the same second, and a rewritten value
  // would be indistinguishable from the preserved one.
  final DateTime recorded = DateTime(2020, 1, 1, 9, 30);

  Future<int> insertRow(AppDatabase db) async {
    final int categoryId = (await db.getCategories(type: 'expense')).first.id;
    return db.insertTransaction(TransactionsCompanion.insert(
      type: 'expense',
      amount: 10,
      categoryId: categoryId,
      date: DateTime(2026, 10, 15),
      createdAt: Value(recorded),
    ));
  }

  Future<Transaction> rowById(AppDatabase db, int id) =>
      (db.select(db.transactions)..where((t) => t.id.equals(id))).getSingle();

  sqliteTest('an edit through the repository keeps the creation time', (AppDatabase db) async {
    final int id = await insertRow(db);
    final TransactionRepositoryImpl repository = TransactionRepositoryImpl(db);

    // The row as the edit page loads it. If the entity did not carry the stored value,
    // the page would have nothing truthful to pass back.
    final TransactionEntity loaded = (await repository.getAllTransactions()).single;
    expect(loaded.createdAt, recorded);

    final bool updated = await repository.updateTransaction(
      loaded.copyWith(amount: 25000, note: 'corrected'),
    );

    expect(updated, isTrue);
    final Transaction after = await rowById(db, id);
    expect(after.amount, 25000);
    expect(after.note, 'corrected');
    expect(after.createdAt, recorded,
        reason: 'an edit changes the row, not when the transaction was recorded');
  });

  sqliteTest('an edit writes every column it is given', (AppDatabase db) async {
    final int id = await insertRow(db);
    final Category income = (await db.getCategories(type: 'income')).single;
    final int salaryId =
        (await db.getSubcategories(income.id)).firstWhere((s) => s.name == 'Salary').id;

    await db.updateTransaction(TransactionsCompanion(
      id: Value(id),
      type: Value(income.type),
      amount: const Value(42000.0),
      categoryId: Value(income.id),
      subcategoryId: Value(salaryId),
      note: const Value('moved'),
      date: Value(DateTime(2026, 9, 2)),
    ));

    final Transaction after = await rowById(db, id);
    expect(after.type, income.type);
    expect(after.amount, 42000.0);
    expect(after.categoryId, income.id);
    expect(after.subcategoryId, salaryId);
    expect(after.note, 'moved');
    expect(after.date, DateTime(2026, 9, 2));
  });
}
