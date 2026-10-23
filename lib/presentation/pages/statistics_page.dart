import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:expense_tracker/domain/entities/category_budget.dart';
import 'package:expense_tracker/domain/entities/month_range.dart';
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
    // Straight from the local table, so it is there within a frame of the page
    // opening. A read that fails leaves the bars out rather than replacing the
    // whole screen with an error: the totals and the rows are still true.
    final List<CategoryBudget> budgets =
        ref.watch(budgetsProvider).valueOrNull ?? const <CategoryBudget>[];

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
            final monthly =
                transactions.where((t) => range.contains(t.date)).toList();
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
                  ..._buildExpenseTab(summary, expenses, budgets)
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

  List<Widget> _buildExpenseTab(
    SummaryResult summary,
    List<TransactionEntity> expenses,
    List<CategoryBudget> budgets,
  ) {
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
      if (summary.expenseByCategory.isNotEmpty || budgets.isNotEmpty)
        _budgetSection(summary, budgets),
    ];
  }

  /// The spending breakdown, with each row measured against its ceiling.
  ///
  /// The rows are the union of what was spent and what has a ceiling: a budget
  /// set for a category that has no spending this month still shows, at zero
  /// spent, which is also the only way to reach it again to change or drop it.
  Widget _budgetSection(SummaryResult summary, List<CategoryBudget> budgets) {
    final Map<String, double> ceilings = <String, double>{
      for (final CategoryBudget budget in budgets)
        if (budget.type == 'expense') budget.name: budget.amount,
    };

    final List<BudgetProgress> rows = <String>{
      ...summary.expenseByCategory.keys,
      ...ceilings.keys,
    }
        .map((String name) => BudgetProgress(
              name: name,
              spent: summary.expenseByCategory[name] ?? 0,
              budget: ceilings[name],
            ))
        .toList()
      ..sort((BudgetProgress a, BudgetProgress b) {
        if (a.spent != b.spent) return b.spent.compareTo(a.spent);
        return a.name.compareTo(b.name);
      });

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Expense by Category',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(
              'Tap a category to set its monthly budget',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
            const SizedBox(height: 16),
            if (summary.expenseByCategory.isNotEmpty) ...[
              CategoryPieChart(data: summary.expenseByCategory),
              const SizedBox(height: 8),
            ],
            ...rows.map((BudgetProgress row) => _budgetRow(row, summary.totalExpense)),
          ],
        ),
      ),
    );
  }

  Widget _budgetRow(BudgetProgress row, double total) {
    final Color color = _categoryColor(row.name);
    final TextTheme text = Theme.of(context).textTheme;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: color.withOpacity(0.15),
        child: Icon(_categoryIcon(row.name), size: 18, color: color),
      ),
      title: Text(row.name),
      subtitle: row.budget == null ? null : _budgetBar(row),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            _fmt(row.spent),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          if (row.budget != null)
            Text(
              row.isOver
                  ? 'over by ${_fmt(row.spent - row.budget!)}'
                  : 'of ${_fmt(row.budget!)}',
              style: TextStyle(fontSize: 12, color: text.bodySmall?.color),
            )
          else if (total > 0)
            // Unbudgeted rows keep the share of the month they used to show.
            Text(
              '${(row.spent / total * 100).toStringAsFixed(1)}%',
              style: TextStyle(fontSize: 12, color: text.bodySmall?.color),
            ),
        ],
      ),
      onTap: () => _editBudget(row.name, row.budget),
    );
  }

  Widget _budgetBar(BudgetProgress row) {
    final double? ratio = row.ratio;
    // Green while there is room, amber in the last fifth, red once it is past.
    // A full red bar for a ceiling of zero: everything spent is over it.
    final Color bar = ratio == null || ratio > 1
        ? Colors.red
        : ratio > 0.8
            ? Colors.orange
            : Colors.green;
    final double filled = ratio == null ? 1 : ratio.clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: filled,
                minHeight: 6,
                backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(bar),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            row.isOver
                ? 'over'
                : '${((ratio ?? 0) * 100).toStringAsFixed(0)}%',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: row.isOver ? Colors.red : Theme.of(context).textTheme.bodySmall?.color,
            ),
          ),
        ],
      ),
    );
  }

  /// Sets, changes or drops the ceiling on [name].
  ///
  /// A zero answers the same way as Remove: a ceiling of zero would put every
  /// category with any spending instantly over budget, which is not a state
  /// worth offering.
  Future<void> _editBudget(String name, double? current) async {
    final double? result = await showDialog<double>(
      context: context,
      builder: (dialogContext) => _BudgetDialog(name: name, current: current),
    );

    if (result == null || !mounted) return;
    if (result <= 0) {
      await ref.read(clearBudgetUseCaseProvider).call(name: name, type: 'expense');
    } else {
      await ref.read(setBudgetUseCaseProvider).call(
            name: name,
            type: 'expense',
            amount: result,
          );
    }
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
    final MonthRange range = _range;
    final daysInMonth = range.dayCount;
    final firstDay = range.start;
    // weekday: Monday=1, Sunday=7. Days until the first Sunday:
    final daysToFirstSunday = firstDay.weekday == 7 ? 0 : 7 - firstDay.weekday;
    final firstSunday = daysToFirstSunday + 1;

    final totals = <int, double>{};
    for (final t in txns) {
      final day = t.date.day;
      int week;
      if (day <= firstSunday) {
        // Week 1: from the 1st up to and including the first Sunday
        week = 1;
      } else {
        // Subsequent weeks: full Mon–Sun blocks
        week = 2 + ((day - firstSunday - 1) ~/ 7);
      }
      totals[week] = (totals[week] ?? 0) + t.amount;
    }

    final weeks = totals.keys.toList()..sort();
    return weeks.map((w) {
      int startDay, endDay;
      if (w == 1) {
        startDay = 1;
        endDay = firstSunday;
      } else {
        final weekOffset = w - 2;
        startDay = firstSunday + 1 + (weekOffset * 7);
        endDay = startDay + 6;
      }
      if (endDay > daysInMonth) endDay = daysInMonth;
      final start = range.day(startDay);
      final end = range.day(endDay);
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

/// The dialog that sets, changes or drops one ceiling.
///
/// It keeps the controller as state because the field outlives the `await` in
/// [_StatisticsPageState._editBudget]: the route is still animating out when a
/// controller created in that method would be disposed, and the widget rebuilds
/// during the transition — which is a "used after being disposed" crash.
class _BudgetDialog extends StatefulWidget {
  const _BudgetDialog({required this.name, required this.current});

  final String name;
  final double? current;

  @override
  State<_BudgetDialog> createState() => _BudgetDialogState();
}

class _BudgetDialogState extends State<_BudgetDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.current?.toStringAsFixed(0) ?? '',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final String digits = _controller.text.replaceAll(RegExp(r'[^0-9]'), '');
    // An empty field answers `null`, not zero: zero drops the ceiling, and
    // clearing the field to retype an amount should not delete one. Remove is
    // how a ceiling is dropped.
    Navigator.pop(context, digits.isEmpty ? null : double.tryParse(digits));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Budget for ${widget.name}'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          labelText: 'Monthly ceiling',
          prefixText: 'Rp ',
        ),
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        if (widget.current != null)
          TextButton(
            onPressed: () => Navigator.pop(context, 0.0),
            child: const Text('Remove'),
          ),
        FilledButton(
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
