// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'transaction_entity.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

TransactionEntity _$TransactionEntityFromJson(Map<String, dynamic> json) {
  return _TransactionEntity.fromJson(json);
}

/// @nodoc
mixin _$TransactionEntity {
  int get id => throw _privateConstructorUsedError;
  String get type => throw _privateConstructorUsedError; // 'income' | 'expense'
  double get amount => throw _privateConstructorUsedError;
  int get categoryId => throw _privateConstructorUsedError;
  int? get subcategoryId => throw _privateConstructorUsedError;
  String? get categoryName => throw _privateConstructorUsedError;
  String? get subcategoryName => throw _privateConstructorUsedError;
  String? get note => throw _privateConstructorUsedError;
  DateTime get date => throw _privateConstructorUsedError;
  DateTime get createdAt => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $TransactionEntityCopyWith<TransactionEntity> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $TransactionEntityCopyWith<$Res> {
  factory $TransactionEntityCopyWith(
          TransactionEntity value, $Res Function(TransactionEntity) then) =
      _$TransactionEntityCopyWithImpl<$Res, TransactionEntity>;
  @useResult
  $Res call(
      {int id,
      String type,
      double amount,
      int categoryId,
      int? subcategoryId,
      String? categoryName,
      String? subcategoryName,
      String? note,
      DateTime date,
      DateTime createdAt});
}

/// @nodoc
class _$TransactionEntityCopyWithImpl<$Res, $Val extends TransactionEntity>
    implements $TransactionEntityCopyWith<$Res> {
  _$TransactionEntityCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? type = null,
    Object? amount = null,
    Object? categoryId = null,
    Object? subcategoryId = freezed,
    Object? categoryName = freezed,
    Object? subcategoryName = freezed,
    Object? note = freezed,
    Object? date = null,
    Object? createdAt = null,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as int,
      type: null == type
          ? _value.type
          : type // ignore: cast_nullable_to_non_nullable
              as String,
      amount: null == amount
          ? _value.amount
          : amount // ignore: cast_nullable_to_non_nullable
              as double,
      categoryId: null == categoryId
          ? _value.categoryId
          : categoryId // ignore: cast_nullable_to_non_nullable
              as int,
      subcategoryId: freezed == subcategoryId
          ? _value.subcategoryId
          : subcategoryId // ignore: cast_nullable_to_non_nullable
              as int?,
      categoryName: freezed == categoryName
          ? _value.categoryName
          : categoryName // ignore: cast_nullable_to_non_nullable
              as String?,
      subcategoryName: freezed == subcategoryName
          ? _value.subcategoryName
          : subcategoryName // ignore: cast_nullable_to_non_nullable
              as String?,
      note: freezed == note
          ? _value.note
          : note // ignore: cast_nullable_to_non_nullable
              as String?,
      date: null == date
          ? _value.date
          : date // ignore: cast_nullable_to_non_nullable
              as DateTime,
      createdAt: null == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$TransactionEntityImplCopyWith<$Res>
    implements $TransactionEntityCopyWith<$Res> {
  factory _$$TransactionEntityImplCopyWith(_$TransactionEntityImpl value,
          $Res Function(_$TransactionEntityImpl) then) =
      __$$TransactionEntityImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {int id,
      String type,
      double amount,
      int categoryId,
      int? subcategoryId,
      String? categoryName,
      String? subcategoryName,
      String? note,
      DateTime date,
      DateTime createdAt});
}

/// @nodoc
class __$$TransactionEntityImplCopyWithImpl<$Res>
    extends _$TransactionEntityCopyWithImpl<$Res, _$TransactionEntityImpl>
    implements _$$TransactionEntityImplCopyWith<$Res> {
  __$$TransactionEntityImplCopyWithImpl(_$TransactionEntityImpl _value,
      $Res Function(_$TransactionEntityImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? type = null,
    Object? amount = null,
    Object? categoryId = null,
    Object? subcategoryId = freezed,
    Object? categoryName = freezed,
    Object? subcategoryName = freezed,
    Object? note = freezed,
    Object? date = null,
    Object? createdAt = null,
  }) {
    return _then(_$TransactionEntityImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as int,
      type: null == type
          ? _value.type
          : type // ignore: cast_nullable_to_non_nullable
              as String,
      amount: null == amount
          ? _value.amount
          : amount // ignore: cast_nullable_to_non_nullable
              as double,
      categoryId: null == categoryId
          ? _value.categoryId
          : categoryId // ignore: cast_nullable_to_non_nullable
              as int,
      subcategoryId: freezed == subcategoryId
          ? _value.subcategoryId
          : subcategoryId // ignore: cast_nullable_to_non_nullable
              as int?,
      categoryName: freezed == categoryName
          ? _value.categoryName
          : categoryName // ignore: cast_nullable_to_non_nullable
              as String?,
      subcategoryName: freezed == subcategoryName
          ? _value.subcategoryName
          : subcategoryName // ignore: cast_nullable_to_non_nullable
              as String?,
      note: freezed == note
          ? _value.note
          : note // ignore: cast_nullable_to_non_nullable
              as String?,
      date: null == date
          ? _value.date
          : date // ignore: cast_nullable_to_non_nullable
              as DateTime,
      createdAt: null == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$TransactionEntityImpl implements _TransactionEntity {
  const _$TransactionEntityImpl(
      {required this.id,
      required this.type,
      required this.amount,
      required this.categoryId,
      this.subcategoryId,
      this.categoryName,
      this.subcategoryName,
      this.note,
      required this.date,
      required this.createdAt});

  factory _$TransactionEntityImpl.fromJson(Map<String, dynamic> json) =>
      _$$TransactionEntityImplFromJson(json);

  @override
  final int id;
  @override
  final String type;
// 'income' | 'expense'
  @override
  final double amount;
  @override
  final int categoryId;
  @override
  final int? subcategoryId;
  @override
  final String? categoryName;
  @override
  final String? subcategoryName;
  @override
  final String? note;
  @override
  final DateTime date;
  @override
  final DateTime createdAt;

  @override
  String toString() {
    return 'TransactionEntity(id: $id, type: $type, amount: $amount, categoryId: $categoryId, subcategoryId: $subcategoryId, categoryName: $categoryName, subcategoryName: $subcategoryName, note: $note, date: $date, createdAt: $createdAt)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$TransactionEntityImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.type, type) || other.type == type) &&
            (identical(other.amount, amount) || other.amount == amount) &&
            (identical(other.categoryId, categoryId) ||
                other.categoryId == categoryId) &&
            (identical(other.subcategoryId, subcategoryId) ||
                other.subcategoryId == subcategoryId) &&
            (identical(other.categoryName, categoryName) ||
                other.categoryName == categoryName) &&
            (identical(other.subcategoryName, subcategoryName) ||
                other.subcategoryName == subcategoryName) &&
            (identical(other.note, note) || other.note == note) &&
            (identical(other.date, date) || other.date == date) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, id, type, amount, categoryId,
      subcategoryId, categoryName, subcategoryName, note, date, createdAt);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$TransactionEntityImplCopyWith<_$TransactionEntityImpl> get copyWith =>
      __$$TransactionEntityImplCopyWithImpl<_$TransactionEntityImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$TransactionEntityImplToJson(
      this,
    );
  }
}

abstract class _TransactionEntity implements TransactionEntity {
  const factory _TransactionEntity(
      {required final int id,
      required final String type,
      required final double amount,
      required final int categoryId,
      final int? subcategoryId,
      final String? categoryName,
      final String? subcategoryName,
      final String? note,
      required final DateTime date,
      required final DateTime createdAt}) = _$TransactionEntityImpl;

  factory _TransactionEntity.fromJson(Map<String, dynamic> json) =
      _$TransactionEntityImpl.fromJson;

  @override
  int get id;
  @override
  String get type;
  @override // 'income' | 'expense'
  double get amount;
  @override
  int get categoryId;
  @override
  int? get subcategoryId;
  @override
  String? get categoryName;
  @override
  String? get subcategoryName;
  @override
  String? get note;
  @override
  DateTime get date;
  @override
  DateTime get createdAt;
  @override
  @JsonKey(ignore: true)
  _$$TransactionEntityImplCopyWith<_$TransactionEntityImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
