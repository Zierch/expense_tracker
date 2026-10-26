/// One transaction read out of a backup file.
///
/// A backup carries the names the rows had in the install that wrote it, not
/// this install's ids, so an imported row arrives as names and is given ids
/// here — that is the whole point of the split between this class and
/// [TransactionEntity].
class ImportTransaction {
  final DateTime date;
  final String type; // 'income' | 'expense'
  final double amount;
  final String categoryName;
  final String? subcategoryName;
  final String? note;

  const ImportTransaction({
    required this.date,
    required this.type,
    required this.amount,
    required this.categoryName,
    this.subcategoryName,
    this.note,
  });
}

/// What one import did to the database.
class ImportWriteResult {
  const ImportWriteResult({required this.imported, required this.duplicates});

  /// Rows written.
  final int imported;

  /// Rows that were already there, matched on content.
  final int duplicates;
}
