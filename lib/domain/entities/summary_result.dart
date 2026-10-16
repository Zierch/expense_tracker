class SummaryResult {
  final double totalIncome;
  final double totalExpense;
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
