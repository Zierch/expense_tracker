import 'package:expense_tracker/domain/entities/transaction_entity.dart';
import 'package:expense_tracker/domain/entities/import_transaction.dart';

abstract class TransactionRepository {
  Future<List<TransactionEntity>> getAllTransactions();
  Stream<List<TransactionEntity>> watchAllTransactions();
  Future<List<TransactionEntity>> getTransactionsByDateRange(
      DateTime start, DateTime end);
  Future<int> insertTransaction(TransactionEntity transaction);
  Future<bool> updateTransaction(TransactionEntity transaction);
  Future<int> deleteTransaction(int id);
  Future<double> getTotalIncome({DateTime? start, DateTime? end});
  Future<double> getTotalExpense({DateTime? start, DateTime? end});
  Future<Map<String, double>> getExpenseByCategory(
      {DateTime? start, DateTime? end});
  Future<Map<String, double>> getIncomeByCategory(
      {DateTime? start, DateTime? end});

  /// Writes a backup's rows, making the categories they name when this install
  /// does not have them yet.
  ///
  /// One transaction for the whole list: a restore that failed halfway would
  /// leave half a month behind, and the user would have no way to tell which
  /// half. Duplicates — rows already stored with the same content — are counted
  /// and left alone.
  Future<ImportWriteResult> importTransactions(
      List<ImportTransaction> transactions);
}
