import 'dart:convert';

import 'package:expense_tracker/domain/entities/import_transaction.dart';
import 'package:expense_tracker/domain/repositories/transaction_repository.dart';
import 'package:intl/intl.dart';

/// A failure whose message is already phrased for the user.
class ImportException implements Exception {
  ImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// What one backup file did when it was imported.
class ImportResult {
  const ImportResult({
    required this.monthLabel,
    required this.imported,
    required this.duplicates,
    required this.unreadable,
  });

  /// `October 2026`, or `''` when the file did not say which month it holds.
  final String monthLabel;

  /// Rows written to the database.
  final int imported;

  /// Rows already stored with the same content.
  final int duplicates;

  /// Rows the file got wrong — an amount that is not a number, a date that does
  /// not parse, a type that is neither income nor expense. Counted rather than
  /// guessed at, because inventing a value for a row the user cannot see is
  /// worse than telling them one row did not come through.
  final int unreadable;

  int get total => imported + duplicates + unreadable;
}

/// Reads a month backup and writes its rows.
///
/// The file is the app's own `expense-tracker-<YYYY-MM>.json`, so the shape is
/// not negotiated at runtime — but it is still treated as input from outside:
/// every field is type-checked, every number is bounded, and a file that claims
/// to come from a newer version is refused rather than half-read.
class ImportMonthUseCase {
  ImportMonthUseCase(this._repository);

  final TransactionRepository _repository;

  /// The highest `schemaVersion` this build knows how to read.
  static const int _supportedSchema = 1;

  /// A backup is one month, so thousands of rows is already absurd; this is a
  /// ceiling on how much a single hand-crafted file can make the app allocate.
  static const int maxTransactions = 10000;

  /// Mirrors the column widths the database enforces, plus room for a note.
  static const int _maxNameLength = 50;
  static const int _maxNoteLength = 500;

  /// A trillion rupiah, which is more than a month can hold. Above this the file
  /// is not describing a transaction, and accepting it would put an `Infinity`
  /// into a total that the summary card then draws as `NaN`.
  static const double _maxAmount = 1e12;

  static final DateFormat _monthLabel = DateFormat('MMMM yyyy');

  Future<ImportResult> call(String jsonText) async {
    final Map<String, dynamic> document = _decode(jsonText);
    final List<ImportTransaction> rows = <ImportTransaction>[];
    int unreadable = 0;

    final Object? rawTransactions = document['transactions'];
    if (rawTransactions is! List<Object?>) {
      throw ImportException(
        'That file has no transactions in it. It does not look like an '
        'Expense Tracker backup.',
      );
    }
    if (rawTransactions.length > maxTransactions) {
      throw ImportException(
        'That file holds ${rawTransactions.length} transactions, more than this '
        'app will import at once ($maxTransactions). Split it by month and try '
        'again.',
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

    final ImportWriteResult written =
        await _repository.importTransactions(rows);

    return ImportResult(
      monthLabel: _readMonthLabel(document),
      imported: written.imported,
      duplicates: written.duplicates,
      unreadable: unreadable,
    );
  }

  Map<String, dynamic> _decode(String jsonText) {
    final Object? decoded;
    try {
      decoded = jsonDecode(jsonText);
    } on FormatException {
      throw ImportException('That file is not readable as JSON.');
    } catch (_) {
      // Not a `FormatException` but still not a parse: brackets nested tens of
      // thousands deep run the parser out of stack, which is an `Error` rather
      // than an exception. A file from outside is not allowed to end the app's
      // process over it.
      throw ImportException('That file could not be read as JSON.');
    }

    if (decoded is! Map<String, dynamic>) {
      throw ImportException('That file is not an Expense Tracker backup.');
    }

    final Object? app = decoded['app'];
    if (app is String && app != 'Expense Tracker') {
      throw ImportException(
          'That file was written by "$app", not Expense Tracker.');
    }

    // `num`, not `int`: a file that says `2.0` is a newer format just as much as
    // one that says `2`, and reading it as "old" because of the dot would be the
    // one mistake this check exists to prevent.
    final Object? schema = decoded['schemaVersion'];
    if (schema is num && schema > _supportedSchema) {
      throw ImportException(
        'That backup was written by a newer version of the app (file format '
        '$schema, this build reads $_supportedSchema). Update the app and try '
        'again.',
      );
    }

    return decoded;
  }

  /// One row of the file, or `null` when the file's own row is not usable.
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

    // An absent field is fine — most transactions have no note. A field that is
    // *there* and unusable is not: dropping it would file the row under its bare
    // category and quietly change what the user wrote. The row goes instead, and
    // is counted as one that could not be read.
    final Object? rawSubcategory = entry['subcategory'];
    final String? subcategoryName = _readName(rawSubcategory, _maxNameLength);
    if (_hasValue(rawSubcategory) && subcategoryName == null) return null;

    final Object? rawNote = entry['note'];
    final String? note = _readName(rawNote, _maxNoteLength);
    if (_hasValue(rawNote) && note == null) return null;

    return ImportTransaction(
      // Backups written before the add page normalised its dates can carry a
      // time of day. A transaction is a calendar day here, so the import drops
      // it rather than storing an instant that no other row has.
      date: DateTime(parsed.year, parsed.month, parsed.day),
      type: rawType,
      amount: amount,
      categoryName: category,
      subcategoryName: subcategoryName,
      note: note,
    );
  }

  /// Whether the file said anything at all for this field.
  ///
  /// `null` and an empty string both mean "none", and both are common: the
  /// export writes `null` for a transaction without a note and a blank for one
  /// with only spaces.
  static bool _hasValue(Object? value) =>
      value != null && value is String && value.trim().isNotEmpty;

  /// A trimmed, non-empty string within [limit], or `null`.
  ///
  /// Control characters are refused along with the length: a name from a file is
  /// drawn on the dashboard, in the statistics list and in the PDF, and a
  /// right-to-left override or an embedded newline there is a name that reads as
  /// something other than what it is. No name typed in the app can contain one,
  /// so a file carrying one did not come from this app's own export.
  String? _readName(Object? value, int limit) {
    if (value == null) return null;
    if (value is! String) return null;

    final String trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.length > limit) return null;
    if (trimmed.runes.any(_isUnsafeRune)) return null;
    return trimmed;
  }

  /// A character that has no place in a category name or a note.
  ///
  /// The whole set matters, not the two obvious characters: a right-to-left
  /// override is only one of the ways a string can draw as something other than
  /// what it says. The other direction markers, the isolates that end them, the
  /// zero-width characters that make two different names look identical, and the
  /// C1 block are all in here for the same reason — a name from a file is drawn
  /// on the dashboard, in the statistics list and in the PDF, and none of these
  /// can be typed into the app's own form.
  static bool _isUnsafeRune(int rune) {
    const int delete = 0x7F;
    const int c1Start = 0x80;
    const int c1End = 0x9F;
    const int zeroWidthSpace = 0x200B;
    const int leftToRightMark = 0x200E;
    const int rightToLeftMark = 0x200F;
    const int arabicLetterMark = 0x61C;
    // LRE, RLE, PDF, LRO and RLO: the whole embedding and override run.
    const int leftToRightEmbedding = 0x202A;
    const int rightToLeftOverride = 0x202E;
    const int leftToRightIsolate = 0x2066;
    const int rightToLeftIsolate = 0x2069;
    const int byteOrderMark = 0xFEFF;

    if (rune < 0x20) return true; // newlines, tabs, and the rest of C0
    if (rune == delete) return true;
    if (rune >= c1Start && rune <= c1End) return true;
    if (rune == arabicLetterMark) return true;
    if (rune >= zeroWidthSpace && rune <= leftToRightMark) return true;
    if (rune == rightToLeftMark) return true;
    if (rune >= leftToRightEmbedding && rune <= rightToLeftOverride)
      return true;
    if (rune >= leftToRightIsolate && rune <= rightToLeftIsolate) return true;
    if (rune == byteOrderMark) return true;
    return false;
  }

  String _readMonthLabel(Map<String, dynamic> document) {
    final Object? period = document['period'];
    if (period is! Map<String, dynamic>) return '';

    final Object? year = period['year'];
    final Object? month = period['month'];
    if (year is! int || month is! int || month < 1 || month > 12) return '';
    // A year outside this band is not a month a person kept records in, and
    // asking `DateTime` to hold one throws rather than returning something
    // sensible — so it is refused before the call, not caught after it.
    if (year < 1900 || year > 2200) return '';

    return _monthLabel.format(DateTime(year, month));
  }
}
