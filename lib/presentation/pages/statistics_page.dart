import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:expense_tracker/domain/entities/summary_result.dart';
import 'package:expense_tracker/domain/entities/transaction_entity.dart';
import 'package:expense_tracker/presentation/providers/providers.dart';
import 'package:expense_tracker/presentation/widgets/category_pie_chart.dart';

class StatisticsPage extends ConsumerStatefulWidget {
  const StatisticsPage({super.key});

  @override
  ConsumerState<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends ConsumerState<StatisticsPage> {
  DateTime _selectedMonth = DateTime.now();
  int _tabIndex = 0; // 0 = Expense, 1 = Income

  @override
  Widget build(BuildContext context) {
    final startOfMonth = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
    final endOfMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0, 23, 59, 59);

    final summaryAsync = ref.watch(summaryProvider(start: startOfMonth, end: endOfMonth));
    final transactionsAsync = ref.watch(transactionsStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Statistics'),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month),
            onPressed: _pickMonth,
            tooltip: 'Select Month',
          ),
        ],
      ),
      body: summaryAsync.when(
        data: (summary) => transactionsAsync.when(
          data: (transactions) {
            final monthly = transactions
                .where((t) => !t.date.isBefore(startOfMonth) && !t.date.isAfter(endOfMonth))
                .toList();
            final expenses = monthly.where((t) => t.isExpense).toList();
            final incomes = monthly.where((t) => t.isIncome).toList();

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                _buildHeader(),
                const SizedBox(height: 16),
                _buildTabSelector(),
                const SizedBox(height: 16),
                if (_tabIndex == 0)
                  ..._buildExpenseTab(summary, expenses)
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
    );
  }

  Widget _buildHeader() {
    return Text(
      DateFormat('MMMM yyyy').format(_selectedMonth),
      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
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

  List<Widget> _buildExpenseTab(SummaryResult summary, List<TransactionEntity> expenses) {
    return [
      _totalCard('Total Expense (Monthly)', summary.totalExpense, Colors.red, Icons.north_east_rounded),
      const SizedBox(height: 16),
      _bucketSection(
        title: 'Weekly Summary',
        subtitle: 'Total expense per week this month',
        buckets: _weeklyBuckets(expenses),
        color: Colors.red,
        emptyText: 'No expense this month',
      ),
      const SizedBox(height: 16),
      _bucketSection(
        title: 'Daily Detail',
        subtitle: 'Total expense per day this month',
        buckets: _dailyBuckets(expenses),
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

  List<_Bucket> _weeklyBuckets(List<TransactionEntity> txns) {
    final daysInMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0).day;
    final totals = <int, double>{};
    for (final t in txns) {
      final week = ((t.date.day - 1) ~/ 7) + 1;
      totals[week] = (totals[week] ?? 0) + t.amount;
    }
    final weeks = totals.keys.toList()..sort();
    return weeks.map((w) {
      final startDay = (w - 1) * 7 + 1;
      final endDay = (w * 7) > daysInMonth ? daysInMonth : (w * 7);
      final start = DateTime(_selectedMonth.year, _selectedMonth.month, startDay);
      final end = DateTime(_selectedMonth.year, _selectedMonth.month, endDay);
      return _Bucket(
        'Week $w  ·  ${DateFormat('d MMM').format(start)} – ${DateFormat('d MMM').format(end)}',
        totals[w]!,
      );
    }).toList();
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

  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedMonth,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDatePickerMode: DatePickerMode.year,
    );
    if (picked != null) setState(() => _selectedMonth = picked);
  }
}

class _Bucket {
  final String label;
  final double total;

  _Bucket(this.label, this.total);
}
