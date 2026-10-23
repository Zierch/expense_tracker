import 'package:expense_tracker/domain/entities/transaction_entity.dart';
import 'package:expense_tracker/domain/entities/category_budget.dart';
import 'package:expense_tracker/domain/entities/recurring_template.dart';

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
  Stream<List<CategoryBudget>> watchBudgets();
  Future<void> setBudget({required String name, required String type, required double amount});
  Future<void> clearBudget({required String name, required String type});
  Stream<List<RecurringTemplateEntity>> watchRecurringTemplates();
  Future<int> addRecurringTemplate(RecurringTemplateEntity template);
  Future<void> setRecurringTemplateActive(int id, bool active);
  Future<int> deleteRecurringTemplate(int id);
  Future<int> applyRecurringTemplates(DateTime now);
}