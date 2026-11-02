class SummaryResult {
  final double totalIncome;
  final double totalExpense;

  /// Everything left up to the end of the period, not just what the period did.
  ///
  /// The income and expense above describe one month; this figure carries, so the
  /// dashboard's balance on the 1st is the previous month's leftover rather than zero.
  final double balance;
  final Map<String, double> expenseByCategory;
  final Map<String, double> incomeByCategory;

  SummaryResult({
    required this.totalIncome,
    required this.totalExpense,
    required this.balance,
    required this.expenseByCategory,
    required this.incomeByCategory,
  });
}
