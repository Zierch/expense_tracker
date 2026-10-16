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