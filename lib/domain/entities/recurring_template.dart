/// A transaction that comes back every month.
///
/// The day is held between 1 and 28 (see `RecurringTemplates` in the database)
/// so that the row exists in February too.
class RecurringTemplateEntity {
  final int id;
  final String type; // 'income' | 'expense'
  final double amount;
  final int categoryId;
  final int? subcategoryId;
  final String? note;
  final int dayOfMonth;
  final bool active;

  /// Names are for drawing the list. A template that is being written does not
  /// have them yet — the row it points at does — so they are nullable here.
  final String? categoryName;
  final String? subcategoryName;

  /// The day this month's row was written; null until the first one.
  final DateTime? lastGeneratedOn;

  const RecurringTemplateEntity({
    required this.id,
    required this.type,
    required this.amount,
    required this.categoryId,
    this.subcategoryId,
    this.note,
    required this.dayOfMonth,
    required this.active,
    this.categoryName,
    this.subcategoryName,
    this.lastGeneratedOn,
  });

  String get displayCategory => subcategoryName ?? categoryName ?? 'Uncategorized';
  bool get isIncome => type == 'income';

  /// The latest day a template may stand on, so every month can hold it.
  static const int maxDay = 28;

  static int clampDay(int day) => day < 1 ? 1 : (day > maxDay ? maxDay : day);
}
