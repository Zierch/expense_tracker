import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:expense_tracker/domain/entities/month_range.dart';
import 'package:expense_tracker/domain/entities/summary_result.dart';
import 'package:expense_tracker/domain/entities/transaction_entity.dart';
import 'package:expense_tracker/presentation/providers/providers.dart';
import 'package:expense_tracker/presentation/widgets/category_pie_chart.dart';
import 'package:expense_tracker/presentation/widgets/month_selector.dart';

class StatisticsPage extends ConsumerStatefulWidget {
  /// The month this page opens on. Today's when omitted, which is the only thing the
  /// app itself ever wants; a test hands one in so a fixture date is not a race
  /// against the clock.
  final DateTime? initialMonth;

  const StatisticsPage({super.key, this.initialMonth});

  @override
  ConsumerState<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends ConsumerState<StatisticsPage> {
  late DateTime _selectedMonth = widget.initialMonth ?? DateTime.now();
  int _tabIndex = 0; // 0 = Expense, 1 = Income

  /// The one month this page describes.
  ///
  /// The SQL totals and the in-memory buckets both derive from it, so a list and the
  /// total above it cannot end up covering different days.
  MonthRange get _range => MonthRange.of(_selectedMonth);

  @override
  Widget build(BuildContext context) {
    final MonthRange range = _range;

    final summaryAsync =
        ref.watch(summaryProvider(start: range.start, end: range.end));
    final transactionsAsync = ref.watch(transactionsStreamProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Statistics')),
      body: Column(
        children: [
          // The same selector the dashboard uses: this page filters by one month and
          // nothing finer, so the calendar icon and its day picker asked for a day
          // whose value went nowhere. Above the list rather than inside it, so the
          // label keeps the dashboard's alignment instead of stacking its padding.
          MonthSelector(
            month: _selectedMonth,
            onChanged: (DateTime month) =>
                setState(() => _selectedMonth = month),
          ),
          Expanded(
            child: summaryAsync.when(
              data: (summary) => transactionsAsync.when(
                data: (transactions) {
                  final monthly =
                      transactions.where((t) => range.contains(t.date)).toList();
                  final expenses = monthly.where((t) => t.isExpense).toList();
                  final incomes = monthly.where((t) => t.isIncome).toList();

                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    children: [
                      _buildTabSelector(),
                      const SizedBox(height: 16),
                      if (_tabIndex == 0)
                        ..._buildExpenseTab(summary, expenses, transactions)
                      else
                        ..._buildIncomeTab(summary, incomes),
                    ],
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabSelector() {
    return SegmentedButton<int>(
      segments: const [
        ButtonSegment(
          value: 0,
          label: Text('Expense'),
          icon: Icon(Icons.north_east_rounded),
        ),
        ButtonSegment(
          value: 1,
          label: Text('Income'),
          icon: Icon(Icons.south_west_rounded),
        ),
      ],
      selected: {_tabIndex},
      onSelectionChanged: (s) => setState(() => _tabIndex = s.first),
      showSelectedIcon: false,
    );
  }

  List<Widget> _buildExpenseTab(
    SummaryResult summary,
    List<TransactionEntity> monthlyExpenses,
    List<TransactionEntity> allTransactions,
  ) {
    final allExpenses = allTransactions.where((t) => t.isExpense).toList();
    return [
      _totalCard('Total Expense (Monthly)', summary.totalExpense, Colors.red, Icons.north_east_rounded),
      const SizedBox(height: 16),
      _bucketSection(
        title: 'Weekly Summary',
        subtitle: 'Monday–Sunday totals; the edge weeks can include the month '
            'before or after',
        buckets: _weeklyBuckets(allExpenses),
        color: Colors.red,
        emptyText: 'No expense this month',
      ),
      const SizedBox(height: 16),
      _bucketSection(
        title: 'Daily Detail',
        subtitle: 'Total expense per day this month',
        buckets: _dailyBuckets(monthlyExpenses),
        color: Colors.orange,
        emptyText: 'No expense this month',
      ),
      const SizedBox(height: 16),
      if (summary.expenseByCategory.isNotEmpty)
        _categorySection('Expense by Category', summary.expenseByCategory, summary.totalExpense),
    ];
  }

  List<Widget> _buildIncomeTab(SummaryResult summary, List<TransactionEntity> incomes) {
    return [
      _totalCard('Total Income (Monthly)', summary.totalIncome, Colors.green, Icons.south_west_rounded),
      const SizedBox(height: 16),
      if (summary.incomeByCategory.isNotEmpty)
        _categorySection('Income by Category', summary.incomeByCategory, summary.totalIncome)
      else
        _emptyCard('No income this month'),
    ];
  }

  Widget _totalCard(String title, double value, Color color, IconData icon) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: color.withOpacity(0.15),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).textTheme.bodySmall?.color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _fmt(value),
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _bucketSection({
    required String title,
    required String subtitle,
    required List<_Bucket> buckets,
    required Color color,
    required String emptyText,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
            const SizedBox(height: 8),
            if (buckets.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  emptyText,
                  style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color),
                ),
              )
            else
              ...buckets.map(
                (b) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(b.label, style: const TextStyle(fontSize: 14)),
                      Text(
                        _fmt(b.total),
                        style: TextStyle(fontWeight: FontWeight.bold, color: color),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _categorySection(String title, Map<String, double> data, double total) {
    final entries = data.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            CategoryPieChart(data: data),
            const SizedBox(height: 8),
            ...entries.map((e) {
              final color = _categoryColor(e.key);
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 18,
                  backgroundColor: color.withOpacity(0.15),
                  child: Icon(_categoryIcon(e.key), size: 18, color: color),
                ),
                title: Text(e.key),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _fmt(e.value),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    if (total > 0)
                      Text(
                        '${(e.value / total * 100).toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).textTheme.bodySmall?.color,
                        ),
                      ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _emptyCard(String text) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            text,
            style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color),
          ),
        ),
      ),
    );
  }

  /// One row per week that holds at least one expense.
  ///
  /// [txns] is deliberately every expense, not the month's: the weeks come from
  /// [MonthRange.weeks] and a week keeps the days it reaches into the neighbouring
  /// month, which is the whole reason a spend on September's last days shows up in
  /// October at all.
  List<_Bucket> _weeklyBuckets(List<TransactionEntity> txns) {
    final List<WeekSpan> weeks = _range.weeks;
    final List<_Bucket> buckets = <_Bucket>[];

    for (int index = 0; index < weeks.length; index++) {
      final WeekSpan week = weeks[index];
      double total = 0;
      bool any = false;
      for (final TransactionEntity t in txns) {
        if (!week.contains(t.date)) continue;
        total += t.amount;
        any = true;
      }
      if (!any) continue;

      buckets.add(_Bucket(
        'Week ${index + 1}  ·  ${DateFormat('d MMM').format(week.start)}'
        ' – ${DateFormat('d MMM').format(week.lastDay)}',
        total,
      ));
    }

    return buckets;
  }

  List<_Bucket> _dailyBuckets(List<TransactionEntity> txns) {
    final totals = <String, double>{};
    final dates = <String, DateTime>{};
    for (final t in txns) {
      final key = DateFormat('yyyy-MM-dd').format(t.date);
      totals[key] = (totals[key] ?? 0) + t.amount;
      dates[key] = t.date;
    }
    final keys = totals.keys.toList()..sort((a, b) => b.compareTo(a));
    return keys
        .map((k) => _Bucket(DateFormat('EEE, d MMM').format(dates[k]!), totals[k]!))
        .toList();
  }

  String _fmt(double v) =>
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(v);

  Color _categoryColor(String name) {
    switch (name.toLowerCase()) {
      case 'food':
        return Colors.orange;
      case 'other needs':
        return Colors.blue;
      case 'data/internet package':
        return Colors.purple;
      case 'salary':
        return Colors.green;
      case 'freelance':
        return Colors.teal;
      case 'investment':
        return Colors.indigo;
      case 'allowance':
        return Colors.amber;
      case 'bonus':
      case 'gift':
        return Colors.pink;
      default:
        return Colors.blueGrey;
    }
  }

  IconData _categoryIcon(String name) {
    switch (name.toLowerCase()) {
      case 'food':
        return Icons.restaurant;
      case 'other needs':
        return Icons.shopping_bag;
      case 'data/internet package':
        return Icons.wifi;
      case 'salary':
        return Icons.work;
      case 'freelance':
        return Icons.laptop_mac;
      case 'investment':
        return Icons.trending_up;
      case 'allowance':
        return Icons.account_balance_wallet;
      case 'bonus':
        return Icons.card_giftcard;
      case 'gift':
        return Icons.redeem;
      default:
        return Icons.category;
    }
  }
}

class _Bucket {
  final String label;
  final double total;

  _Bucket(this.label, this.total);
}
