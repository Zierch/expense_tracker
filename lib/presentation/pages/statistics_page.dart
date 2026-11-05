import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:expense_tracker/domain/entities/month_range.dart';
import 'package:expense_tracker/domain/entities/summary_result.dart';
import 'package:expense_tracker/domain/entities/transaction_entity.dart';
import 'package:expense_tracker/presentation/providers/providers.dart';
import 'package:expense_tracker/presentation/widgets/category_pie_chart.dart';
import 'package:expense_tracker/presentation/widgets/month_selector.dart';

// ponytail: Design tokens scoped locally until shared DesignSystem token package is extracted.
abstract final class _StatisticsDesign {
  // Brand colors
  static const Color primary = Color(0xFF0E5A44);

  // Light theme tokens
  static const Color lightBackground = Color(0xFFF4F6F8);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightText = Color(0xFF111827);
  static const Color lightMuted = Color(0xFF6B7280);
  static const Color lightBorder = Color(0xFFE5E7EB);
  static const Color lightExpense = Color(0xFFD64545);
  static const Color lightIncome = Color(0xFF2E9E5B);

  // Dark theme tokens
  static const Color darkBackground = Color(0xFF101916);
  static const Color darkSurface = Color(0xFF1B2924);
  static const Color darkTinted = Color(0xFF244239);
  static const Color darkText = Color(0xFFEDF7F1);
  static const Color darkMuted = Color(0xFFA8BDB3);
  static const Color darkBorder = Color(0xFF31443A);
  static const Color darkAccent = Color(0xFF83DFB7);
  static const Color darkExpense = Color(0xFFFF8A8A);
  static const Color darkIncome = Color(0xFF83DFB7);

}

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

    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color backgroundColor =
        isDark ? _StatisticsDesign.darkBackground : _StatisticsDesign.lightBackground;
    final Color surfaceColor =
        isDark ? _StatisticsDesign.darkSurface : _StatisticsDesign.lightSurface;
    final Color textColor =
        isDark ? _StatisticsDesign.darkText : _StatisticsDesign.lightText;
    final Color mutedColor =
        isDark ? _StatisticsDesign.darkMuted : _StatisticsDesign.lightMuted;
    final Color borderColor =
        isDark ? _StatisticsDesign.darkBorder : _StatisticsDesign.lightBorder;
    final Color expenseColor =
        isDark ? _StatisticsDesign.darkExpense : _StatisticsDesign.lightExpense;
    final Color incomeColor =
        isDark ? _StatisticsDesign.darkIncome : _StatisticsDesign.lightIncome;
    final Color dailyColor =
        isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: Text(
          'Statistics',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: textColor,
          ),
        ),
        automaticallyImplyLeading: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
      ),
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
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                    children: [
                      _buildTabSelector(
                        isDark: isDark,
                        surfaceColor: surfaceColor,
                        borderColor: borderColor,
                        mutedColor: mutedColor,
                      ),
                      const SizedBox(height: 16),
                      if (_tabIndex == 0)
                        ..._buildExpenseTab(
                          summary: summary,
                          monthlyExpenses: expenses,
                          allTransactions: transactions,
                          textColor: textColor,
                          mutedColor: mutedColor,
                          surfaceColor: surfaceColor,
                          borderColor: borderColor,
                          expenseColor: expenseColor,
                          dailyColor: dailyColor,
                        )
                      else
                        ..._buildIncomeTab(
                          summary: summary,
                          incomes: incomes,
                          textColor: textColor,
                          mutedColor: mutedColor,
                          surfaceColor: surfaceColor,
                          borderColor: borderColor,
                          incomeColor: incomeColor,
                        ),
                    ],
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      'Error: $e',
                      style: TextStyle(
                        color: isDark
                            ? const Color(0xFFFF9393)
                            : Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ),
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    'Error: $e',
                    style: TextStyle(
                      color: isDark
                          ? const Color(0xFFFF9393)
                          : Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabSelector({
    required bool isDark,
    required Color surfaceColor,
    required Color borderColor,
    required Color mutedColor,
  }) {
    final activeColor =
        isDark ? _StatisticsDesign.darkTinted : const Color(0xFFD1FAE5);
    final activeTextColor =
        isDark ? _StatisticsDesign.darkAccent : _StatisticsDesign.primary;

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
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith<Color>((states) {
          if (states.contains(WidgetState.selected)) {
            return activeColor;
          }
          return surfaceColor;
        }),
        foregroundColor: WidgetStateProperty.resolveWith<Color>((states) {
          if (states.contains(WidgetState.selected)) {
            return activeTextColor;
          }
          return mutedColor;
        }),
        side: WidgetStatePropertyAll<BorderSide>(
          BorderSide(color: borderColor),
        ),
        shape: WidgetStatePropertyAll<OutlinedBorder>(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        textStyle: const WidgetStatePropertyAll<TextStyle>(
          TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  List<Widget> _buildExpenseTab({
    required SummaryResult summary,
    required List<TransactionEntity> monthlyExpenses,
    required List<TransactionEntity> allTransactions,
    required Color textColor,
    required Color mutedColor,
    required Color surfaceColor,
    required Color borderColor,
    required Color expenseColor,
    required Color dailyColor,
  }) {
    final allExpenses = allTransactions.where((t) => t.isExpense).toList();
    return [
      _totalCard(
        title: 'Total Expense (Monthly)',
        value: summary.totalExpense,
        color: expenseColor,
        icon: Icons.north_east_rounded,
        textColor: textColor,
        mutedColor: mutedColor,
        surfaceColor: surfaceColor,
        borderColor: borderColor,
      ),
      const SizedBox(height: 16),
      _bucketSection(
        title: 'Weekly Summary',
        subtitle: 'Monday–Sunday totals; the edge weeks can include the month '
            'before or after',
        buckets: _weeklyBuckets(allExpenses),
        color: expenseColor,
        emptyText: 'No expense this month',
        surfaceColor: surfaceColor,
        borderColor: borderColor,
        textColor: textColor,
        mutedColor: mutedColor,
      ),
      const SizedBox(height: 16),
      _bucketSection(
        title: 'Daily Detail',
        subtitle: 'Total expense per day this month',
        buckets: _dailyBuckets(monthlyExpenses),
        color: dailyColor,
        emptyText: 'No expense this month',
        surfaceColor: surfaceColor,
        borderColor: borderColor,
        textColor: textColor,
        mutedColor: mutedColor,
      ),
      const SizedBox(height: 16),
      if (summary.expenseByCategory.isNotEmpty)
        _categorySection(
          title: 'Expense by Category',
          data: summary.expenseByCategory,
          total: summary.totalExpense,
          surfaceColor: surfaceColor,
          borderColor: borderColor,
          textColor: textColor,
          mutedColor: mutedColor,
        ),
    ];
  }

  List<Widget> _buildIncomeTab({
    required SummaryResult summary,
    required List<TransactionEntity> incomes,
    required Color textColor,
    required Color mutedColor,
    required Color surfaceColor,
    required Color borderColor,
    required Color incomeColor,
  }) {
    return [
      _totalCard(
        title: 'Total Income (Monthly)',
        value: summary.totalIncome,
        color: incomeColor,
        icon: Icons.south_west_rounded,
        textColor: textColor,
        mutedColor: mutedColor,
        surfaceColor: surfaceColor,
        borderColor: borderColor,
      ),
      const SizedBox(height: 16),
      if (summary.incomeByCategory.isNotEmpty)
        _categorySection(
          title: 'Income by Category',
          data: summary.incomeByCategory,
          total: summary.totalIncome,
          surfaceColor: surfaceColor,
          borderColor: borderColor,
          textColor: textColor,
          mutedColor: mutedColor,
        )
      else
        _emptyCard(
          'No income this month',
          surfaceColor: surfaceColor,
          borderColor: borderColor,
          mutedColor: mutedColor,
        ),
    ];
  }

  Widget _totalCard({
    required String title,
    required double value,
    required Color color,
    required IconData icon,
    required Color textColor,
    required Color mutedColor,
    required Color surfaceColor,
    required Color borderColor,
  }) {
    return Card(
      elevation: 0,
      color: surfaceColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withOpacity(0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: mutedColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _fmt(value),
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ],
              ),
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
    required Color surfaceColor,
    required Color borderColor,
    required Color textColor,
    required Color mutedColor,
  }) {
    return Card(
      elevation: 0,
      color: surfaceColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: mutedColor,
              ),
            ),
            const SizedBox(height: 12),
            if (buckets.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  emptyText,
                  style: TextStyle(color: mutedColor),
                ),
              )
            else
              ...buckets.asMap().entries.map((entry) {
                final int idx = entry.key;
                final _Bucket b = entry.value;
                return Column(
                  children: [
                    if (idx > 0)
                      Divider(color: borderColor, height: 16, thickness: 1),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            b.label,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: textColor,
                            ),
                          ),
                          Text(
                            _fmt(b.total),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: color,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _categorySection({
    required String title,
    required Map<String, double> data,
    required double total,
    required Color surfaceColor,
    required Color borderColor,
    required Color textColor,
    required Color mutedColor,
  }) {
    final entries = data.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return Card(
      elevation: 0,
      color: surfaceColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
            ),
            const SizedBox(height: 16),
            CategoryPieChart(data: data),
            const SizedBox(height: 12),
            ...entries.asMap().entries.map((entry) {
              final int idx = entry.key;
              final e = entry.value;
              final color = _categoryColor(e.key);
              return Column(
                children: [
                  if (idx > 0)
                    Divider(color: borderColor, height: 16, thickness: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.14),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(_categoryIcon(e.key), size: 18, color: color),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            e.key,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: textColor,
                            ),
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              _fmt(e.value),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: textColor,
                              ),
                            ),
                            if (total > 0)
                              Text(
                                '${(e.value / total * 100).toStringAsFixed(1)}%',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: mutedColor,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _emptyCard(
    String text, {
    required Color surfaceColor,
    required Color borderColor,
    required Color mutedColor,
  }) {
    return Card(
      elevation: 0,
      color: surfaceColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 14,
              color: mutedColor,
            ),
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
        return const Color(0xFFF59E0B);
      case 'other needs':
        return const Color(0xFF3B82F6);
      case 'data/internet package':
        return const Color(0xFF8B5CF6);
      case 'salary':
        return const Color(0xFF10B981);
      case 'freelance':
        return const Color(0xFF14B8A6);
      case 'investment':
        return const Color(0xFF6366F1);
      case 'allowance':
        return const Color(0xFFEAB308);
      case 'bonus':
      case 'gift':
        return const Color(0xFFEC4899);
      default:
        return const Color(0xFF64748B);
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
