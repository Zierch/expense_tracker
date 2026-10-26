import 'package:drift/drift.dart';
import 'package:expense_tracker/data/database/app_database.dart';
import 'package:expense_tracker/domain/entities/import_transaction.dart';
import 'package:expense_tracker/domain/entities/transaction_entity.dart';
import 'package:expense_tracker/domain/repositories/transaction_repository.dart';

class TransactionRepositoryImpl implements TransactionRepository {
  final AppDatabase _database;

  TransactionRepositoryImpl(this._database);

  @override
  Future<List<TransactionEntity>> getAllTransactions() async {
    final rows = await _database.getTransactionsWithJoinedNames();
    return rows.map(_toEntity).toList();
  }

  @override
  Stream<List<TransactionEntity>> watchAllTransactions() {
    return _database
        .watchTransactionsWithJoinedNames()
        .map((rows) => rows.map(_toEntity).toList());
  }

  @override
  Future<List<TransactionEntity>> getTransactionsByDateRange(
      DateTime start, DateTime end) async {
    final rows =
        await _database.getTransactionsByDateRangeWithNames(start, end);
    return rows.map(_toEntity).toList();
  }

  @override
  Future<int> insertTransaction(TransactionEntity transaction) {
    return _database.insertTransaction(TransactionsCompanion(
      type: Value(transaction.type),
      amount: Value(transaction.amount),
      categoryId: Value(transaction.categoryId),
      subcategoryId: Value(transaction.subcategoryId),
      note: Value(transaction.note),
      date: Value(transaction.date),
    ));
  }

  @override
  Future<bool> updateTransaction(TransactionEntity transaction) {
    return _database.updateTransaction(TransactionsCompanion(
      id: Value(transaction.id),
      type: Value(transaction.type),
      amount: Value(transaction.amount),
      categoryId: Value(transaction.categoryId),
      subcategoryId: Value(transaction.subcategoryId),
      note: Value(transaction.note),
      date: Value(transaction.date),
    ));
  }

  @override
  Future<int> deleteTransaction(int id) {
    return _database.deleteTransaction(id);
  }

  @override
  Future<double> getTotalIncome({DateTime? start, DateTime? end}) {
    return _database.getTotalIncome(start: start, end: end);
  }

  @override
  Future<double> getTotalExpense({DateTime? start, DateTime? end}) {
    return _database.getTotalExpense(start: start, end: end);
  }

  @override
  Future<Map<String, double>> getExpenseByCategory(
      {DateTime? start, DateTime? end}) {
    return _database.getExpenseByCategory(start: start, end: end);
  }

  @override
  Future<Map<String, double>> getIncomeByCategory(
      {DateTime? start, DateTime? end}) {
    return _database.getIncomeByCategory(start: start, end: end);
  }

  @override
  Future<ImportWriteResult> importTransactions(
      List<ImportTransaction> transactions) {
    return _database.transaction(() async {
      int imported = 0;
      int duplicates = 0;

      for (final ImportTransaction transaction in transactions) {
        final int categoryId = await _database.findOrCreateCategory(
            transaction.categoryName, transaction.type);
        final String? subcategoryName = transaction.subcategoryName;
        final int? subcategoryId = subcategoryName == null
            ? null
            : await _database.findOrCreateSubcategory(
                subcategoryName, categoryId);

        final bool alreadyStored = await _database.hasMatchingTransaction(
          date: transaction.date,
          type: transaction.type,
          amount: transaction.amount,
          categoryId: categoryId,
          subcategoryId: subcategoryId,
          note: transaction.note,
        );
        if (alreadyStored) {
          duplicates++;
          continue;
        }

        await _database.insertTransaction(TransactionsCompanion.insert(
          type: transaction.type,
          amount: transaction.amount,
          categoryId: categoryId,
          subcategoryId: Value(subcategoryId),
          note: Value(transaction.note),
          date: transaction.date,
          // The backup has no creation time to restore, and the dashboard orders
          // one day's rows by it, so the row's own date is the honest fill: it
          // keeps a day's imported rows in the order they were stored rather than
          // in the order a clock happened to be read.
          createdAt: Value(transaction.date),
        ));
        imported++;
      }

      return ImportWriteResult(imported: imported, duplicates: duplicates);
    });
  }

  TransactionEntity _toEntity(TransactionWithNames row) {
    return TransactionEntity(
      id: row.transaction.id,
      type: row.transaction.type,
      amount: row.transaction.amount,
      categoryId: row.transaction.categoryId,
      subcategoryId: row.transaction.subcategoryId,
      categoryName: row.categoryName,
      subcategoryName: row.subcategoryName,
      note: row.transaction.note,
      date: row.transaction.date,
      createdAt: row.transaction.createdAt,
    );
  }
}
