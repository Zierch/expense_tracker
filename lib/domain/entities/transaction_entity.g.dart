// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'transaction_entity.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$TransactionEntityImpl _$$TransactionEntityImplFromJson(
        Map<String, dynamic> json) =>
    _$TransactionEntityImpl(
      id: (json['id'] as num).toInt(),
      type: json['type'] as String,
      amount: (json['amount'] as num).toDouble(),
      categoryId: (json['categoryId'] as num).toInt(),
      subcategoryId: (json['subcategoryId'] as num?)?.toInt(),
      categoryName: json['categoryName'] as String?,
      subcategoryName: json['subcategoryName'] as String?,
      note: json['note'] as String?,
      date: DateTime.parse(json['date'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );

Map<String, dynamic> _$$TransactionEntityImplToJson(
        _$TransactionEntityImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'type': instance.type,
      'amount': instance.amount,
      'categoryId': instance.categoryId,
      'subcategoryId': instance.subcategoryId,
      'categoryName': instance.categoryName,
      'subcategoryName': instance.subcategoryName,
      'note': instance.note,
      'date': instance.date.toIso8601String(),
      'createdAt': instance.createdAt.toIso8601String(),
    };
