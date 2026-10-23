import 'package:expense_tracker/domain/entities/category_budget.dart';
import 'package:expense_tracker/domain/repositories/transaction_repository.dart';

class WatchBudgetsUseCase {
  final TransactionRepository _repository;

  WatchBudgetsUseCase(this._repository);

  Stream<List<CategoryBudget>> call() => _repository.watchBudgets();
}

class SetBudgetUseCase {
  final TransactionRepository _repository;

  SetBudgetUseCase(this._repository);

  Future<void> call({
    required String name,
    required String type,
    required double amount,
  }) =>
      _repository.setBudget(name: name, type: type, amount: amount);
}

class ClearBudgetUseCase {
  final TransactionRepository _repository;

  ClearBudgetUseCase(this._repository);

  Future<void> call({required String name, required String type}) =>
      _repository.clearBudget(name: name, type: type);
}
