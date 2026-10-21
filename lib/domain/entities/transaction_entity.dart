import 'package:freezed_annotation/freezed_annotation.dart';

part 'transaction_entity.freezed.dart';
part 'transaction_entity.g.dart';

@freezed
class TransactionEntity with _$TransactionEntity {
  const factory TransactionEntity({
    required int id,
    required String type, // 'income' | 'expense'
    required double amount,
    required int categoryId,
    int? subcategoryId,
    String? categoryName,
    String? subcategoryName,
    String? note,
    required DateTime date,
    required DateTime createdAt,
  }) = _TransactionEntity;

  factory TransactionEntity.fromJson(Map<String, dynamic> json) => _$TransactionEntityFromJson(json);
}

extension TransactionEntityX on TransactionEntity {
  bool get isIncome => type == 'income';
  bool get isExpense => type == 'expense';
  String get displayCategory => subcategoryName ?? categoryName ?? 'Uncategorized';
}

/// Newest first, with the same tie-breakers the list's SQL uses.
///
/// `date` is a calendar day, so a day's rows tie on it and `createdAt` then `id` decide
/// — without them `List.sort` (which is not stable) left the on-screen order to chance.
/// `id` last also keeps rows apart when a day's rows were recorded in the same second,
/// which is the ordinary case for a few entries typed one after another.
int newestFirst(TransactionEntity a, TransactionEntity b) {
  final int byDate = b.date.compareTo(a.date);
  if (byDate != 0) return byDate;
  final int byCreatedAt = b.createdAt.compareTo(a.createdAt);
  if (byCreatedAt != 0) return byCreatedAt;
  return b.id.compareTo(a.id);
}