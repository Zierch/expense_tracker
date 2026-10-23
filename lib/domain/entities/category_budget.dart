/// A monthly ceiling for one row of the spending breakdown.
///
/// [name] is the display name the statistics list, the pie chart and the PDF
/// already group by — `subcategoryName ?? categoryName` — so a budget and the
/// row it sits next to cannot drift apart.
class CategoryBudget {
  final String name;
  final String type; // 'income' | 'expense'
  final double amount;

  const CategoryBudget({
    required this.name,
    required this.type,
    required this.amount,
  });
}

/// A breakdown row plus the ceiling it is measured against, if it has one.
class BudgetProgress {
  final String name;
  final double spent;
  final double? budget;

  const BudgetProgress({
    required this.name,
    required this.spent,
    this.budget,
  });

  /// How much of the ceiling is used, or `null` when there is no ceiling.
  ///
  /// A ceiling of zero has no meaningful ratio — everything is infinitely over
  /// it — so it reports `null` and the row draws a full, red bar instead.
  double? get ratio => (budget == null || budget == 0) ? null : spent / budget!;

  /// What is left of the ceiling, negative once it is passed.
  double? get remaining => budget == null ? null : budget! - spent;

  bool get isOver => budget != null && spent > budget!;
}
