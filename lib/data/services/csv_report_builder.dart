import 'package:expense_tracker/domain/entities/transaction_entity.dart';
import 'package:intl/intl.dart';

/// The header row, in the order the fields below are written.
///
/// Named the way the app names them rather than the way the columns are called
/// in SQLite: this file is opened by a person, in a spreadsheet, and a `type`
/// column that says `expense` is already the app's own word for it.
const List<String> csvColumns = <String>[
  'date',
  'type',
  'category',
  'subcategory',
  'amount',
  'note',
];

final DateFormat _isoDate = DateFormat('yyyy-MM-dd');

/// [rows] as the text of a CSV file, in the order given.
///
/// The byte-order mark comes first because a spreadsheet that reads a UTF-8 CSV
/// without one falls back to the local code page, which turns a category name
/// into mojibake. `\r\n` line endings and the quoting are RFC 4180, which is the
/// dialect every spreadsheet agrees on.
String buildCsvReport(List<TransactionEntity> rows) {
  final StringBuffer out = StringBuffer('\uFEFF');
  out.write(csvColumns.map(_field).join(','));
  out.write('\r\n');

  for (final TransactionEntity row in rows) {
    out.write(<String>[
      _isoDate.format(row.date),
      row.type,
      row.categoryName ?? '',
      row.subcategoryName ?? '',
      _amount(row.amount),
      row.note ?? '',
    ].map(_field).join(','));
    out.write('\r\n');
  }

  return out.toString();
}

/// One field, quoted when RFC 4180 says it has to be.
///
/// Only then, so an amount stays a number to the spreadsheet instead of arriving
/// as text. Quoting everything would be simpler and would make every column a
/// string, which is the one thing a CSV of amounts must not do.
String _field(String value) {
  final String safe = _neutraliseFormula(value);
  final bool needsQuotes = safe.contains(',') ||
      safe.contains('"') ||
      safe.contains('\n') ||
      safe.contains('\r');
  return needsQuotes ? '"${safe.replaceAll('"', '""')}"' : safe;
}

/// A `'` in front of a field whose first *visible* character can start a formula.
///
/// `=`, `+`, `-` and `@` are how a spreadsheet is told "this cell is a formula",
/// and a note is a string the app did not necessarily receive from its own form: a
/// backup file can carry one. Importing such a file and then exporting a CSV
/// would turn somebody else's text into something this spreadsheet is asked to
/// evaluate — with the file's author choosing what. The apostrophe is the
/// spreadsheet's own "this is text" marker, so the note still reads as the note.
///
/// The first *visible* character, not `value[0]`: a note can be saved untrimmed, and
/// a spreadsheet that trims a cell on import would then evaluate what followed the
/// space. Leading whitespace is stepped over first, which is also why the apostrophe
/// goes in front of the whole value rather than after the space.
String _neutraliseFormula(String value) {
  const String formulaStarts = '=+-@';
  int start = 0;
  while (start < value.length && _isLeadingWhitespace(value[start])) {
    start++;
  }
  if (start >= value.length) return value;
  return formulaStarts.contains(value[start]) ? "'$value" : value;
}

bool _isLeadingWhitespace(String character) =>
    character == ' ' ||
    character == '\t' ||
    character == '\r' ||
    character == '\n';

/// A number a spreadsheet reads as a number: `250000`, not `250000.0`.
///
/// At most two decimals, because that is what an amount in rupiah means: a value
/// that needed more would be a rounding artefact of `double` arithmetic rather
/// than something somebody entered, and a CSV full of `0.30000000000000004` is
/// worse than one that says `0.30`.
String _amount(double value) =>
    value.toStringAsFixed(value == value.roundToDouble() ? 0 : 2);
