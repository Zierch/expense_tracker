import 'package:drift/drift.dart';
import 'package:expense_tracker/data/database/app_database.dart';
import 'package:expense_tracker/domain/entities/import_transaction.dart';
import 'package:expense_tracker/domain/entities/subcategory_aliases.dart';
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
  Future<List<DateTime>> getMonthsWithTransactions() {
    return _database.getMonthsWithTransactions();
  }

  @override
  Future<ImportWriteResult> importTransactions(
      List<ImportTransaction> transactions) {
    return _database.transaction(() async {
      int imported = 0;
      int duplicates = 0;
      final Set<int> matchedPreexistingIds = <int>{};
      final Set<int> insertedIds = <int>{};

      for (final ImportTransaction transaction in transactions) {
        final int categoryId = await _database.findOrCreateCategory(
            transaction.categoryName, transaction.type);
        final String? subcategoryName = transaction.subcategoryName;
        // A backup names subcategories as strings, and a file outlives the
        // release that wrote it: the ones the app itself renamed are folded back
        // onto today's name here, so restoring a v1.10.x snapshot does not leave
        // a second "Pocket Money" row beside "Allowance".
        //
        // A name that already exists locally wins, though. If the user made a
        // "Pocket Money" of their own, the file means that one, not the app's
        // retired default — so the alias only applies when the file's own name
        // is not already here.
        final int? subcategoryId = subcategoryName == null
            ? null
            : await _database.findOrCreateSubcategory(
                await _importName(
                    subcategoryName, transaction.type, categoryId),
                categoryId);

        final int? matchId = await _database.findMatchingTransactionId(
          date: transaction.date,
          type: transaction.type,
          amount: transaction.amount,
          categoryId: categoryId,
          subcategoryId: subcategoryId,
          note: transaction.note,
          excludedIds: <int>{...matchedPreexistingIds, ...insertedIds},
        );
        if (matchId != null) {
          matchedPreexistingIds.add(matchId);
          duplicates++;
          continue;
        }

        final int newId =
            await _database.insertTransaction(TransactionsCompanion.insert(
          type: transaction.type,
          amount: transaction.amount,
          categoryId: categoryId,
          subcategoryId: Value(subcategoryId),
          note: Value(transaction.note),
          date: transaction.date,
          createdAt: Value(transaction.createdAt ?? transaction.date),
        ));
        insertedIds.add(newId);
        imported++;
      }

      return ImportWriteResult(imported: imported, duplicates: duplicates);
    });
  }

  /// The name a file's subcategory should be stored under.
  ///
  /// Today's name, unless the file's own name is already a real subcategory
  /// here — in which case the file is talking about that one. See
  /// [resolveImportedSubcategoryName] for why any of this exists.
  Future<String> _importName(String name, String type, int categoryId) async {
    final String resolved = resolveImportedSubcategoryName(name, type);
    if (resolved == name) return name;
    if (await _database.findSubcategoryId(name, categoryId) != null) {
      return name;
    }
    return resolved;
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
