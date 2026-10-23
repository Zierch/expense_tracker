import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:expense_tracker/data/database/app_database.dart';
import 'package:expense_tracker/data/repositories/transaction_repository_impl.dart';
import 'package:expense_tracker/domain/entities/transaction_entity.dart';
import 'package:expense_tracker/domain/entities/summary_result.dart';
import 'package:expense_tracker/domain/repositories/transaction_repository.dart';
import 'package:expense_tracker/domain/usecases/transaction_usecases.dart';

part 'providers.g.dart';

@riverpod
AppDatabase database(Ref ref) {
  return AppDatabase();
}

@riverpod
TransactionRepository transactionRepository(Ref ref) {
  return TransactionRepositoryImpl(ref.watch(databaseProvider));
}

@riverpod
GetTransactionsUseCase getTransactionsUseCase(Ref ref) {
  return GetTransactionsUseCase(ref.watch(transactionRepositoryProvider));
}

@riverpod
GetTransactionsByDateRangeUseCase getTransactionsByDateRangeUseCase(Ref ref) {
  return GetTransactionsByDateRangeUseCase(ref.watch(transactionRepositoryProvider));
}

@riverpod
AddTransactionUseCase addTransactionUseCase(Ref ref) {
  return AddTransactionUseCase(ref.watch(transactionRepositoryProvider));
}

@riverpod
UpdateTransactionUseCase updateTransactionUseCase(Ref ref) {
  return UpdateTransactionUseCase(ref.watch(transactionRepositoryProvider));
}

@riverpod
DeleteTransactionUseCase deleteTransactionUseCase(Ref ref) {
  return DeleteTransactionUseCase(ref.watch(transactionRepositoryProvider));
}

@riverpod
GetSummaryUseCase getSummaryUseCase(Ref ref) {
  return GetSummaryUseCase(ref.watch(transactionRepositoryProvider));
}

@riverpod
Stream<List<TransactionEntity>> transactionsStream(Ref ref) {
  return ref.watch(getTransactionsUseCaseProvider).watch();
}

@riverpod
Future<SummaryResult> summary(Ref ref, {DateTime? start, DateTime? end}) {
  // The totals are computed in SQL, which knows nothing about the row stream, so
  // without this line the card kept the numbers it was first built with: adding or
  // deleting a transaction moved the list and left income/expense/balance behind until
  // a pull-to-refresh or a restart. Watching the stream re-runs the queries below on
  // every write. The value is deliberately unused — it is the subscription that matters.
  ref.watch(transactionsStreamProvider);
  return ref.watch(getSummaryUseCaseProvider).call(start: start, end: end);
}