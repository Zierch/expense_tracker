import 'package:expense_tracker/domain/entities/transaction_entity.dart';

abstract class TransactionRepository {
  Future<List<TransactionEntity>> getAllTransactions();
  Stream<List<TransactionEntity>> watchAllTransactions();
  Future<List<TransactionEntity>> getTransactionsByDateRange(DateTime start, DateTime end);
  Future<int> insertTransaction(TransactionEntity transaction);
  Future<bool> updateTransaction(TransactionEntity transaction);
  Future<int> deleteTransaction(int id);
  Future<double> getTotalIncome({DateTime? start, DateTime? end});
  Future<double> getTotalExpense({DateTime? start, DateTime? end});
  Future<Map<String, double>> getExpenseByCategory({DateTime? start, DateTime? end});
  Future<Map<String, double>> getIncomeByCategory({DateTime? start, DateTime? end});
}