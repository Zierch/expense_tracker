import 'dart:convert';

import 'package:expense_tracker/domain/entities/import_transaction.dart';
import 'package:expense_tracker/domain/repositories/transaction_repository.dart';
import 'package:expense_tracker/domain/usecases/import_month_usecase.dart';

/// A failure whose message is phrased for the user.
class SnapshotImportException extends ImportException {
  SnapshotImportException(super.message);
}

/// What one snapshot import did when it was processed.
class SnapshotImportResult {
  const SnapshotImportResult({
    required this.imported,
    required this.duplicates,
    required this.unreadable,
    required this.monthsCount,
    required this.backupType,
  });

  /// Rows written to the database.
  final int imported;

  /// Rows already stored with the same content.
  final int duplicates;

  /// Rows the file got wrong — invalid amounts, unparseable dates, bad types, or unsafe characters.
  final int unreadable;

  /// Count of distinct calendar months represented in the imported valid rows.
  final int monthsCount;

  /// 'snapshot' or 'monthly'.
  final String backupType;

  int get total => imported + duplicates + unreadable;
}

/// Reads a complete snapshot (or legacy monthly backup) and writes its rows non-destructively.
class ImportSnapshotUseCase {
  ImportSnapshotUseCase(this._repository);

  final TransactionRepository _repository;

  /// The highest schemaVersion this build knows how to read.
  static const int _supportedSchema = 1;

  /// A snapshot covers all months, up to 100,000 transactions.
  static const int maxTransactions = 100000;

  /// Column width limits.
  static const int _maxNameLength = 50;
  static const int _maxNoteLength = 500;

  /// Amount ceiling.
  static const double _maxAmount = 1e12;

  Future<SnapshotImportResult> call(String jsonText) async {
    final Map<String, dynamic> document = _decode(jsonText);
    final List<ImportTransaction> rows = <ImportTransaction>[];
    int unreadable = 0;

    final Object? rawTransactions = document['transactions'];
    if (rawTransactions is! List<Object?>) {
      throw SnapshotImportException(
        'That file has no transactions in it. It does not look like an '
        'Expense Tracker backup.',
      );
    }
    if (rawTransactions.length > maxTransactions) {
      throw SnapshotImportException(
        'That file holds ${rawTransactions.length} transactions, more than this '
        'app will import at once ($maxTransactions).',
      );
    }

    for (final Object? entry in rawTransactions) {
      final ImportTransaction? row = _readTransaction(entry);
      if (row == null) {
        unreadable++;
        continue;
      }
      rows.add(row);
    }

    final Set<int> monthKeys = <int>{};
    for (final ImportTransaction row in rows) {
      monthKeys.add(row.date.year * 12 + row.date.month - 1);
    }

    final ImportWriteResult written =
        await _repository.importTransactions(rows);

    return SnapshotImportResult(
      imported: written.imported,
      duplicates: written.duplicates,
      unreadable: unreadable,
      monthsCount: monthKeys.length,
      backupType: _detectBackupType(document),
    );
  }

  String _detectBackupType(Map<String, dynamic> document) {
    final Object? backupType = document['backupType'];
    if (backupType is String && backupType.toLowerCase() == 'snapshot') {
      return 'snapshot';
    }
    final Object? period = document['period'];
    if (period is Map<String, dynamic>) {
      if (period['type'] == 'all') return 'snapshot';
      if (period['year'] != null && period['month'] != null) return 'monthly';
    }
    return 'snapshot';
  }

  Map<String, dynamic> _decode(String jsonText) {
    final Object? decoded;
    try {
      decoded = jsonDecode(jsonText);
    } on FormatException {
      throw SnapshotImportException('That file is not readable as JSON.');
    } catch (_) {
      throw SnapshotImportException('That file could not be read as JSON.');
    }

    if (decoded is! Map<String, dynamic>) {
      throw SnapshotImportException(
          'That file is not an Expense Tracker backup.');
    }

    final Object? app = decoded['app'];
    if (app is String && app != 'Expense Tracker') {
      throw SnapshotImportException(
          'That file was written by "$app", not Expense Tracker.');
    }

    final Object? schema = decoded['schemaVersion'];
    if (schema is num && schema > _supportedSchema) {
      throw SnapshotImportException(
        'That backup was written by a newer version of the app (file format '
        '$schema, this build reads $_supportedSchema). Update the app and try '
        'again.',
      );
    }

    return decoded;
  }

  ImportTransaction? _readTransaction(Object? entry) {
    if (entry is! Map<String, dynamic>) return null;

    final Object? rawType = entry['type'];
    if (rawType is! String) return null;
    if (rawType != 'income' && rawType != 'expense') return null;

    final Object? rawAmount = entry['amount'];
    if (rawAmount is! num) return null;
    final double amount = rawAmount.toDouble();
    if (!amount.isFinite || amount <= 0 || amount > _maxAmount) return null;

    final Object? rawDate = entry['date'];
    if (rawDate is! String) return null;
    final DateTime? parsed = DateTime.tryParse(rawDate);
    if (parsed == null) return null;

    final String? category = _readName(entry['category'], _maxNameLength);
    if (category == null) return null;

    final Object? rawSubcategory = entry['subcategory'];
    final String? subcategoryName = _readName(rawSubcategory, _maxNameLength);
    if (_hasValue(rawSubcategory) && subcategoryName == null) return null;

    final Object? rawNote = entry['note'];
    final String? note = _readName(rawNote, _maxNoteLength);
    if (_hasValue(rawNote) && note == null) return null;

    return ImportTransaction(
      date: DateTime(parsed.year, parsed.month, parsed.day),
      type: rawType,
      amount: amount,
      categoryName: category,
      subcategoryName: subcategoryName,
      note: note,
    );
  }

  static bool _hasValue(Object? value) =>
      value != null && value is String && value.trim().isNotEmpty;

  String? _readName(Object? value, int limit) {
    if (value == null) return null;
    if (value is! String) return null;

    final String trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.length > limit) return null;
    if (trimmed.runes.any(_isUnsafeRune)) return null;
    return trimmed;
  }

  static bool _isUnsafeRune(int rune) {
    const int delete = 0x7F;
    const int c1Start = 0x80;
    const int c1End = 0x9F;
    const int zeroWidthSpace = 0x200B;
    const int leftToRightMark = 0x200E;
    const int rightToLeftMark = 0x200F;
    const int arabicLetterMark = 0x61C;
    const int leftToRightEmbedding = 0x202A;
    const int rightToLeftOverride = 0x202E;
    const int leftToRightIsolate = 0x2066;
    const int rightToLeftIsolate = 0x2069;
    const int byteOrderMark = 0xFEFF;

    if (rune < 0x20) return true;
    if (rune == delete) return true;
    if (rune >= c1Start && rune <= c1End) return true;
    if (rune == arabicLetterMark) return true;
    if (rune >= zeroWidthSpace && rune <= leftToRightMark) return true;
    if (rune == rightToLeftMark) return true;
    if (rune >= leftToRightEmbedding && rune <= rightToLeftOverride) return true;
    if (rune >= leftToRightIsolate && rune <= rightToLeftIsolate) return true;
    if (rune == byteOrderMark) return true;
    return false;
  }
}
