import 'package:expense_tracker/domain/entities/recurring_template.dart';
import 'package:expense_tracker/domain/repositories/transaction_repository.dart';

class WatchRecurringTemplatesUseCase {
  final TransactionRepository _repository;

  WatchRecurringTemplatesUseCase(this._repository);

  Stream<List<RecurringTemplateEntity>> call() => _repository.watchRecurringTemplates();
}

class AddRecurringTemplateUseCase {
  final TransactionRepository _repository;

  AddRecurringTemplateUseCase(this._repository);

  Future<int> call(RecurringTemplateEntity template) =>
      _repository.addRecurringTemplate(template);
}

class SetRecurringTemplateActiveUseCase {
  final TransactionRepository _repository;

  SetRecurringTemplateActiveUseCase(this._repository);

  Future<void> call(int id, bool active) => _repository.setRecurringTemplateActive(id, active);
}

class DeleteRecurringTemplateUseCase {
  final TransactionRepository _repository;

  DeleteRecurringTemplateUseCase(this._repository);

  Future<int> call(int id) => _repository.deleteRecurringTemplate(id);
}

class ApplyRecurringTemplatesUseCase {
  final TransactionRepository _repository;

  ApplyRecurringTemplatesUseCase(this._repository);

  /// Writes this month's rows; returns how many were written.
  Future<int> call([DateTime? now]) => _repository.applyRecurringTemplates(now ?? DateTime.now());
}
