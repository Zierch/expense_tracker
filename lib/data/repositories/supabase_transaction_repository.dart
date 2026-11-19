// The web half of the repository boundary.
//
// Everything the app knows about money lives in the domain layer and is reused
// unchanged here. This class only moves rows between Supabase and
// TransactionEntity: no new rules about categories, dates or totals.
//
// The Android build never instantiates this class. The two implementations are
// selected in `transactionRepositoryProvider` with `kIsWeb`.

import 'package:expense_tracker/domain/entities/import_transaction.dart';
import 'package:expense_tracker/domain/entities/subcategory_aliases.dart';
import 'package:expense_tracker/domain/entities/transaction_entity.dart';
import 'package:expense_tracker/domain/repositories/transaction_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The names the Android app seeds into a fresh database, with their type.
///
/// Kept in Dart rather than in SQL so both platforms share one list. `Allowance`
/// is the name v1.11.0 restored; the v1.10.x `Pocket Money` is never seeded.
const List<(String, String)> _defaultSubcategories = <(String, String)>[
  ('Salary', 'income'),
  ('Freelance', 'income'),
  ('Bonus', 'income'),
  ('Gift', 'income'),
  ('Allowance', 'income'),
  ('Food', 'expense'),
  ('Other Needs', 'expense'),
  ('Data/Internet Package', 'expense'),
  ('Coffee Shop', 'expense'),
  ('Fuel', 'expense'),
];

class SupabaseTransactionRepository implements TransactionRepository {
  SupabaseTransactionRepository(this._client);

  final SupabaseClient _client;

  String get _userId {
    final String? id = _client.auth.currentUser?.id;
    if (id == null) {
      throw StateError('Sign in before reading or writing transactions.');
    }
    return id;
  }

  // ------------------------------------------------------------------- reads

  @override
  Future<List<TransactionEntity>> getAllTransactions() async {
    final List<dynamic> rows = await _orderedRows();
    return rows.cast<Map<String, dynamic>>().map(_toEntity).toList();
  }

  @override
  Stream<List<TransactionEntity>> watchAllTransactions() async* {
    // Realtime would need a channel and a publication per user. v1 does not add
    // one: the stream re-reads when the local list is rebuilt, which covers the
    // app's own writes without claiming to be live across devices.
    yield await getAllTransactions();
  }

  // Embed the names: the snapshot and month exporters write category and
  // subcategory by name, and a bare `select()` would give them nulls even though
  // the rows are there.
  static const String _withNames =
      '*, categories!inner(name), subcategories(name)';

  Future<List<dynamic>> _orderedRows() => _client
      .from('transactions')
      .select(_withNames)
      .eq('user_id', _userId)
      .order('date', ascending: false)
      .order('created_at', ascending: false)
      .order('id', ascending: false);

  @override
  Future<List<TransactionEntity>> getTransactionsByDateRange(
      DateTime start, DateTime end) async {
    final List<dynamic> rows = await _client
        .from('transactions')
        .select(_withNames)
        .eq('user_id', _userId)
        .gte('date', start.toUtc().toIso8601String())
        .lte('date', end.toUtc().toIso8601String())
        .order('date', ascending: false)
        .order('created_at', ascending: false)
        .order('id', ascending: false);
    return rows.cast<Map<String, dynamic>>().map(_toEntity).toList();
  }

  TransactionEntity _toEntity(Map<String, dynamic> row) => TransactionEntity(
        id: row['id'] as int,
        type: row['type'] as String,
        amount: (row['amount'] as num).toDouble(),
        categoryId: row['category_id'] as int,
        subcategoryId: row['subcategory_id'] as int?,
        categoryName: (row['categories'] as Map<String, dynamic>?)?['name']
            as String?,
        subcategoryName:
            (row['subcategories'] as Map<String, dynamic>?)?['name'] as String?,
        note: row['note'] as String?,
        date: DateTime.parse(row['date'] as String).toLocal(),
        createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
      );

  // ------------------------------------------------------------------ writes

  @override
  Future<int> insertTransaction(TransactionEntity transaction) =>
      _insertRow(<String, dynamic>{
        'user_id': _userId,
        'type': transaction.type,
        'amount': transaction.amount,
        'category_id': transaction.categoryId,
        'subcategory_id': transaction.subcategoryId,
        'note': transaction.note,
        'date': transaction.date.toUtc().toIso8601String(),
        'created_at': transaction.createdAt.toUtc().toIso8601String(),
      });

  Future<int> _insertRow(Map<String, dynamic> row) async {
    final List<dynamic> inserted =
        await _client.from('transactions').insert(row).select('id');
    return (inserted.first as Map<String, dynamic>)['id'] as int;
  }

  @override
  Future<bool> updateTransaction(TransactionEntity transaction) async {
    final List<dynamic> updated = await _client
        .from('transactions')
        .update(<String, dynamic>{
          'type': transaction.type,
          'amount': transaction.amount,
          'category_id': transaction.categoryId,
          'subcategory_id': transaction.subcategoryId,
          'note': transaction.note,
          'date': transaction.date.toUtc().toIso8601String(),
        })
        .eq('user_id', _userId)
        .eq('id', transaction.id)
        .select('id');
    return updated.isNotEmpty;
  }

  @override
  Future<int> deleteTransaction(int id) async {
    final List<dynamic> deleted = await _client
        .from('transactions')
        .delete()
        .eq('user_id', _userId)
        .eq('id', id)
        .select('id');
    return deleted.length;
  }

  // --------------------------------------------------------------- aggregates

  /// Android sums in Dart over the rows in the range; doing the same here keeps
  /// the two platforms numerically identical, including rounding.
  @override
  Future<double> getTotalIncome({DateTime? start, DateTime? end}) =>
      _sum('income', start: start, end: end);

  @override
  Future<double> getTotalExpense({DateTime? start, DateTime? end}) =>
      _sum('expense', start: start, end: end);

  Future<double> _sum(String type, {DateTime? start, DateTime? end}) async {
    final List<dynamic> rows = await _amountRows(type, start: start, end: end);
    return rows.fold<double>(
      0,
      (double total, dynamic row) =>
          total + ((row as Map<String, dynamic>)['amount'] as num).toDouble(),
    );
  }

  Future<List<dynamic>> _amountRows(String type,
      {DateTime? start, DateTime? end}) {
    var query = _client
        .from('transactions')
        .select('amount, date')
        .eq('user_id', _userId)
        .eq('type', type);
    if (start != null) {
      query = query.gte('date', start.toUtc().toIso8601String());
    }
    if (end != null) {
      query = query.lte('date', end.toUtc().toIso8601String());
    }
    return query;
  }

  @override
  Future<Map<String, double>> getExpenseByCategory(
          {DateTime? start, DateTime? end}) =>
      _byCategory('expense', start: start, end: end);

  @override
  Future<Map<String, double>> getIncomeByCategory(
          {DateTime? start, DateTime? end}) =>
      _byCategory('income', start: start, end: end);

  /// Android groups by subcategory name when there is one, falling back to the
  /// category name. One joined query does the same here — a query per row would
  /// make Statistics slow in exact proportion to how much data the user entered.
  Future<Map<String, double>> _byCategory(String type,
      {DateTime? start, DateTime? end}) async {
    var query = _client
        .from('transactions')
        .select('amount, date, categories!inner(name), subcategories(name)')
        .eq('user_id', _userId)
        .eq('type', type);
    if (start != null) {
      query = query.gte('date', start.toUtc().toIso8601String());
    }
    if (end != null) {
      query = query.lte('date', end.toUtc().toIso8601String());
    }
    final List<dynamic> rows = await query;

    final Map<String, double> totals = <String, double>{};
    for (final dynamic row in rows) {
      final Map<String, dynamic> map = row as Map<String, dynamic>;
      final String category =
          (map['categories'] as Map<String, dynamic>)['name'] as String;
      final Object? sub = map['subcategories'];
      final String name = sub == null
          ? category
          : (sub as Map<String, dynamic>)['name'] as String? ?? category;
      totals[name] =
          (totals[name] ?? 0) + (map['amount'] as num).toDouble();
    }
    return totals;
  }

  @override
  Future<List<DateTime>> getMonthsWithTransactions() async {
    final List<dynamic> rows =
        await _client.from('transactions').select('date').eq('user_id', _userId);
    final Set<int> keys = <int>{};
    for (final dynamic row in rows) {
      final DateTime date = DateTime.parse((row as Map<String, dynamic>)['date'] as String).toLocal();
      keys.add(date.year * 12 + date.month - 1);
    }
    final List<int> ordered = keys.toList()..sort();
    return ordered
        .map((int key) => DateTime(key ~/ 12, key % 12 + 1))
        .toList();
  }

  // -------------------------------------------------------------------- seed

  /// Called once after the first web login.
  ///
  /// The unique constraints in the schema mean a second call from another tab
  /// cannot leave duplicate categories behind.
  Future<void> ensureSeed() async {
    final String user = _userId;
    final List<dynamic> existing = await _client
        .from('categories')
        .select('id')
        .eq('user_id', user)
        .limit(1);
    if (existing.isNotEmpty) return;

    for (final String type in <String>['income', 'expense']) {
      final List<dynamic> inserted = await _client
          .from('categories')
          .insert(<String, dynamic>{
        'user_id': user,
        'name': type == 'income' ? 'Income' : 'Expense',
        'type': type,
      }).select('id');
      final int categoryId = (inserted.first as Map<String, dynamic>)['id'] as int;
      for (final (String name, String subType) in _defaultSubcategories) {
        if (subType != type) continue;
        await _client.from('subcategories').insert(<String, dynamic>{
          'user_id': user,
          'category_id': categoryId,
          'name': name,
        });
      }
    }
  }

  // ------------------------------------------------------------------- import

  @override
  Future<ImportWriteResult> importTransactions(
      List<ImportTransaction> transactions) async {
    // Supabase Dart has no client-side transaction spanning HTTP requests. The
    // import stays additive and idempotent: a retry matches the rows the first
    // attempt already wrote instead of duplicating them.
    int imported = 0;
    int duplicates = 0;

    for (final ImportTransaction transaction in transactions) {
      final int categoryId = await _findOrCreateCategory(
          transaction.categoryName, transaction.type);
      final String? name = transaction.subcategoryName;
      final int? subcategoryId = name == null
          ? null
          : await _findOrCreateSubcategory(
              await _importName(name, transaction.type, categoryId),
              categoryId);

      final bool already = await _matchesExisting(
        date: transaction.date,
        type: transaction.type,
        amount: transaction.amount,
        categoryId: categoryId,
        subcategoryId: subcategoryId,
        note: transaction.note,
      );
      if (already) {
        duplicates++;
        continue;
      }

      await _insertRow(<String, dynamic>{
        'user_id': _userId,
        'type': transaction.type,
        'amount': transaction.amount,
        'category_id': categoryId,
        'subcategory_id': subcategoryId,
        'note': transaction.note,
        'date': transaction.date.toUtc().toIso8601String(),
        'created_at': (transaction.createdAt ?? transaction.date)
            .toUtc()
            .toIso8601String(),
      });
      imported++;
    }

    return ImportWriteResult(imported: imported, duplicates: duplicates);
  }

  Future<int> _findOrCreateCategory(String name, String type) async {
    final List<dynamic> rows = await _client
        .from('categories')
        .select('id')
        .eq('user_id', _userId)
        .eq('name', name)
        .eq('type', type)
        .limit(1);
    if (rows.isNotEmpty) return (rows.first as Map<String, dynamic>)['id'] as int;
    final List<dynamic> inserted = await _client
        .from('categories')
        .insert(<String, dynamic>{
      'user_id': _userId,
      'name': name,
      'type': type,
    }).select('id');
    return (inserted.first as Map<String, dynamic>)['id'] as int;
  }

  /// The name a file's subcategory should be stored under.
  ///
  /// Same rule as the Drift repository: a name that already exists locally is
  /// the user's own data and wins, so an old backup's "Pocket Money" is only
  /// folded into "Allowance" when this account has no "Pocket Money" of its own.
  Future<String> _importName(String name, String type, int categoryId) async {
    final String resolved = resolveImportedSubcategoryName(name, type);
    if (resolved == name) return name;
    final List<dynamic> rows = await _client
        .from('subcategories')
        .select('id')
        .eq('user_id', _userId)
        .eq('category_id', categoryId)
        .eq('name', name)
        .limit(1);
    if (rows.isNotEmpty) return name;
    return resolved;
  }

  Future<int> _findOrCreateSubcategory(String name, int categoryId) async {
    final List<dynamic> rows = await _client
        .from('subcategories')
        .select('id')
        .eq('user_id', _userId)
        .eq('category_id', categoryId)
        .eq('name', name)
        .limit(1);
    if (rows.isNotEmpty) return (rows.first as Map<String, dynamic>)['id'] as int;
    final List<dynamic> inserted = await _client
        .from('subcategories')
        .insert(<String, dynamic>{
      'user_id': _userId,
      'category_id': categoryId,
      'name': name,
    }).select('id');
    return (inserted.first as Map<String, dynamic>)['id'] as int;
  }

  /// Same-day, same-content match the Drift import uses, so restoring a file
  /// twice writes nothing the second time.
  Future<bool> _matchesExisting({
    required DateTime date,
    required String type,
    required double amount,
    required int categoryId,
    required int? subcategoryId,
    required String? note,
  }) async {
    final DateTime start = DateTime(date.year, date.month, date.day);
    final DateTime end = DateTime(date.year, date.month, date.day + 1);
    var query = _client
        .from('transactions')
        .select('id')
        .eq('user_id', _userId)
        .eq('type', type)
        .eq('amount', amount)
        .eq('category_id', categoryId)
        .gte('date', start.toUtc().toIso8601String())
        .lt('date', end.toUtc().toIso8601String());
    if (subcategoryId == null) {
      query = query.isFilter('subcategory_id', null);
    } else {
      query = query.eq('subcategory_id', subcategoryId);
    }
    if (note == null) {
      query = query.isFilter('note', null);
    } else {
      query = query.eq('note', note);
    }
    final List<dynamic> rows = await query.limit(1);
    return rows.isNotEmpty;
  }
}
