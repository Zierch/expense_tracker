import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:expense_tracker/domain/entities/month_range.dart';
import 'package:expense_tracker/domain/entities/summary_result.dart';
import 'package:expense_tracker/domain/entities/transaction_entity.dart';
import 'package:expense_tracker/presentation/providers/providers.dart';
import 'package:expense_tracker/presentation/pages/backup_page.dart' show ReportCard;
import 'package:expense_tracker/presentation/widgets/category_pie_chart.dart';
import 'package:expense_tracker/presentation/widgets/month_selector.dart';

// ponytail: Design tokens scoped locally until shared DesignSystem token package is extracted.
/// The page's colours and radii.
///
/// Public only so `color_contrast_test.dart` can measure the figures it draws
/// against the surfaces they sit on.
abstract final class StatisticsDesign {
  // Brand colors
  static const Color primary = Color(0xFF0E5A44);

  // Light theme tokens
  static const Color lightBackground = Color(0xFFF4F6F8);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightText = Color(0xFF111827);
  static const Color lightMuted = Color(0xFF6B7280);
  static const Color lightBorder = Color(0xFFE5E7EB);
  /// Income and expense figures on a white card.
  ///
  /// Both were below WCAG AA for body text: `#2E9E5B` sat at 3.41:1 and `#D64545`
  /// at 4.38:1, and the amount on a row is 15px — under the 18.66px bold that
  /// would let it pass as large text. Darkened until they clear 4.5:1 on white
  /// and on the page background; the hue is unchanged, so green still means money
  /// in and red money out.
  static const Color lightExpense = Color(0xFFC53030);
  static const Color lightIncome = Color(0xFF24804A);

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

  /// [color] darkened until it reads on a light tint of itself.
  ///
  /// A pie legend is a colour key, so the glyph has to stay recognisably the
  /// slice's colour — but at full strength on a 14% tint of the same hue the two
  /// are 1.7-2.4:1 apart, which is a smudge rather than an icon. Scaling the
  /// lightness keeps the hue and gets every category past 5:1.
  static Color legibleIconColor(Color color) {
    final HSLColor hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness((hsl.lightness * 0.55).clamp(0.0, 1.0))
        .toColor();
  }
}

enum StatisticsPeriod {
  week,
  month,
  year,
}

class StatisticsPage extends ConsumerStatefulWidget {
  /// The month this page opens on. Today's when omitted, which is the only thing the
  /// app itself ever wants; a test hands one in so a fixture date is not a race
  /// against the clock.
  final DateTime? initialMonth;
  final StatisticsPeriod initialPeriod;

  const StatisticsPage({
    super.key,
    this.initialMonth,
    this.initialPeriod = StatisticsPeriod.month,
  });

  @override
  ConsumerState<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends ConsumerState<StatisticsPage> {
  late DateTime _selectedDate = widget.initialMonth ?? DateTime.now();
  late StatisticsPeriod _period = widget.initialPeriod;
  int _tabIndex = 0; // 0 = Expense, 1 = Income

  /// The month this page describes when in month mode.
  ///
  /// The SQL totals and the in-memory buckets both derive from it, so a list and the
  /// total above it cannot end up covering different days.
  MonthRange get _range => MonthRange.of(_selectedDate);

  @override
  Widget build(BuildContext context) {
    final MonthRange range = _range;
    final WeekSpan currentWeek = range.weeks.firstWhere(
      (w) => w.contains(_selectedDate),
      orElse: () => range.weeks.first,
    );

    final DateTime rangeStart;
    final DateTime rangeEnd;
    final bool Function(DateTime) containsDate;

    switch (_period) {
      case StatisticsPeriod.week:
        rangeStart = currentWeek.start;
        rangeEnd = currentWeek.end;
        containsDate = currentWeek.contains;
        break;
      case StatisticsPeriod.month:
        rangeStart = range.start;
        rangeEnd = range.end;
        containsDate = range.contains;
        break;
      case StatisticsPeriod.year:
        final MonthRange jan = MonthRange.of(DateTime(_selectedDate.year, 1, 1));
        final MonthRange dec = MonthRange.of(DateTime(_selectedDate.year, 12, 1));
        rangeStart = jan.start;
        rangeEnd = dec.end;
        containsDate = (d) => d.year == _selectedDate.year;
        break;
    }

    final summaryAsync =
        ref.watch(summaryProvider(start: rangeStart, end: rangeEnd));
    final transactionsAsync = ref.watch(transactionsStreamProvider);

    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color backgroundColor =
        isDark ? StatisticsDesign.darkBackground : StatisticsDesign.lightBackground;
    final Color surfaceColor =
        isDark ? StatisticsDesign.darkSurface : StatisticsDesign.lightSurface;
    final Color textColor =
        isDark ? StatisticsDesign.darkText : StatisticsDesign.lightText;
    final Color mutedColor =
        isDark ? StatisticsDesign.darkMuted : StatisticsDesign.lightMuted;
    final Color borderColor =
        isDark ? StatisticsDesign.darkBorder : StatisticsDesign.lightBorder;
    final Color expenseColor =
        isDark ? StatisticsDesign.darkExpense : StatisticsDesign.lightExpense;
    final Color incomeColor =
        isDark ? StatisticsDesign.darkIncome : StatisticsDesign.lightIncome;
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
          if (_period == StatisticsPeriod.month)
            MonthSelector(
              month: _selectedDate,
              onChanged: (DateTime month) =>
                  setState(() => _selectedDate = month),
            )
          else if (_period == StatisticsPeriod.week)
            _buildWeekSelector(
              week: currentWeek,
              textColor: textColor,
            )
          else
            _buildYearSelector(
              year: _selectedDate.year,
              textColor: textColor,
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: _buildPeriodSelector(
              isDark: isDark,
              surfaceColor: surfaceColor,
              borderColor: borderColor,
              mutedColor: mutedColor,
            ),
          ),
          Expanded(
            child: summaryAsync.when(
              data: (summary) => transactionsAsync.when(
                data: (transactions) {
                  final inPeriod =
                      transactions.where((t) => containsDate(t.date)).toList();
                  final expenses = inPeriod.where((t) => t.isExpense).toList();
                  final incomes = inPeriod.where((t) => t.isIncome).toList();

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
                          period: _period,
                          summary: summary,
                          periodExpenses: expenses,
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
                          period: _period,
                          summary: summary,
                          periodIncomes: incomes,
                          allTransactions: transactions,
                          textColor: textColor,
                          mutedColor: mutedColor,
                          surfaceColor: surfaceColor,
                          borderColor: borderColor,
                          incomeColor: incomeColor,
                          dailyColor: dailyColor,
                        ),
                      const SizedBox(height: 16),
                      const ReportCard(),
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

  Widget _buildPeriodSelector({
    required bool isDark,
    required Color surfaceColor,
    required Color borderColor,
    required Color mutedColor,
  }) {
    final activeColor =
        isDark ? StatisticsDesign.darkTinted : const Color(0xFFD1FAE5);
    final activeTextColor =
        isDark ? StatisticsDesign.darkAccent : StatisticsDesign.primary;

    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<StatisticsPeriod>(
        segments: const [
          ButtonSegment(
            value: StatisticsPeriod.week,
            label: Text('Week'),
          ),
          ButtonSegment(
            value: StatisticsPeriod.month,
            label: Text('Month'),
          ),
          ButtonSegment(
            value: StatisticsPeriod.year,
            label: Text('Year'),
          ),
        ],
        selected: {_period},
        onSelectionChanged: (s) => setState(() => _period = s.first),
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
            TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }

  Widget _buildWeekSelector({
    required WeekSpan week,
    required Color textColor,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Previous week',
            onPressed: () {
              setState(() {
                _selectedDate = DateTime(
                  _selectedDate.year,
                  _selectedDate.month,
                  _selectedDate.day - 7,
                );
              });
            },
          ),
          Text(
            '${DateFormat('d MMM').format(week.start)} – ${DateFormat('d MMM yyyy').format(week.lastDay)}',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Next week',
            onPressed: () {
              setState(() {
                _selectedDate = DateTime(
                  _selectedDate.year,
                  _selectedDate.month,
                  _selectedDate.day + 7,
                );
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildYearSelector({
    required int year,
    required Color textColor,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Previous year',
            onPressed: () {
              setState(() {
                _selectedDate = DateTime(
                  _selectedDate.year - 1,
                  _selectedDate.month,
                  1,
                );
              });
            },
          ),
          Text(
            '$year',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Next year',
            onPressed: () {
              setState(() {
                _selectedDate = DateTime(
                  _selectedDate.year + 1,
                  _selectedDate.month,
                  1,
                );
              });
            },
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
        isDark ? StatisticsDesign.darkTinted : const Color(0xFFD1FAE5);
    final activeTextColor =
        isDark ? StatisticsDesign.darkAccent : StatisticsDesign.primary;

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
    required StatisticsPeriod period,
    required SummaryResult summary,
    required List<TransactionEntity> periodExpenses,
    required List<TransactionEntity> allTransactions,
    required Color textColor,
    required Color mutedColor,
    required Color surfaceColor,
    required Color borderColor,
    required Color expenseColor,
    required Color dailyColor,
  }) {
    final allExpenses = allTransactions.where((t) => t.isExpense).toList();
    final String totalTitle;
    final String emptyText;
    switch (period) {
      case StatisticsPeriod.week:
        totalTitle = 'Total Expense (Weekly)';
        emptyText = 'No expense this week';
        break;
      case StatisticsPeriod.month:
        totalTitle = 'Total Expense (Monthly)';
        emptyText = 'No expense this month';
        break;
      case StatisticsPeriod.year:
        totalTitle = 'Total Expense (Yearly)';
        emptyText = 'No expense this year';
        break;
    }

    return [
      _totalCard(
        title: totalTitle,
        value: summary.totalExpense,
        previous: _previousTotal(allExpenses),
      ),
      const SizedBox(height: 16),
      if (period == StatisticsPeriod.month) ...[
        _bucketSection(
          title: 'Weekly Summary',
          subtitle: 'Monday–Sunday totals; the edge weeks can include the month '
              'before or after',
          buckets: _weeklyBuckets(allExpenses),
          color: expenseColor,
          emptyText: emptyText,
          surfaceColor: surfaceColor,
          borderColor: borderColor,
          textColor: textColor,
          mutedColor: mutedColor,
        ),
        const SizedBox(height: 16),
        _bucketSection(
          title: 'Daily Detail',
          subtitle: 'Total expense per day this month',
          buckets: _dailyBuckets(periodExpenses),
          color: dailyColor,
          emptyText: emptyText,
          surfaceColor: surfaceColor,
          borderColor: borderColor,
          textColor: textColor,
          mutedColor: mutedColor,
        ),
      ] else if (period == StatisticsPeriod.week) ...[
        _bucketSection(
          title: 'Daily Detail',
          subtitle: 'Total expense per day this week',
          buckets: _dailyBuckets(periodExpenses),
          color: dailyColor,
          emptyText: emptyText,
          surfaceColor: surfaceColor,
          borderColor: borderColor,
          textColor: textColor,
          mutedColor: mutedColor,
        ),
      ] else if (period == StatisticsPeriod.year) ...[
        _bucketSection(
          title: 'Monthly Summary',
          subtitle: 'Total expense per month this year',
          buckets: _monthlyBuckets(periodExpenses),
          color: expenseColor,
          emptyText: emptyText,
          surfaceColor: surfaceColor,
          borderColor: borderColor,
          textColor: textColor,
          mutedColor: mutedColor,
        ),
      ],
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
    required StatisticsPeriod period,
    required SummaryResult summary,
    required List<TransactionEntity> periodIncomes,
    required List<TransactionEntity> allTransactions,
    required Color textColor,
    required Color mutedColor,
    required Color surfaceColor,
    required Color borderColor,
    required Color incomeColor,
    required Color dailyColor,
  }) {
    final allIncomes = allTransactions.where((t) => t.isIncome).toList();
    final String totalTitle;
    final String emptyText;
    switch (period) {
      case StatisticsPeriod.week:
        totalTitle = 'Total Income (Weekly)';
        emptyText = 'No income this week';
        break;
      case StatisticsPeriod.month:
        totalTitle = 'Total Income (Monthly)';
        emptyText = 'No income this month';
        break;
      case StatisticsPeriod.year:
        totalTitle = 'Total Income (Yearly)';
        emptyText = 'No income this year';
        break;
    }

    return [
      _totalCard(
        title: totalTitle,
        value: summary.totalIncome,
        previous: _previousTotal(allIncomes),
      ),
      const SizedBox(height: 16),
      if (period == StatisticsPeriod.month) ...[
        _bucketSection(
          title: 'Weekly Summary',
          subtitle: 'Monday–Sunday totals; the edge weeks can include the month '
              'before or after',
          buckets: _weeklyBuckets(allIncomes),
          color: incomeColor,
          emptyText: emptyText,
          surfaceColor: surfaceColor,
          borderColor: borderColor,
          textColor: textColor,
          mutedColor: mutedColor,
        ),
        const SizedBox(height: 16),
        _bucketSection(
          title: 'Daily Detail',
          subtitle: 'Total income per day this month',
          buckets: _dailyBuckets(periodIncomes),
          color: dailyColor,
          emptyText: emptyText,
          surfaceColor: surfaceColor,
          borderColor: borderColor,
          textColor: textColor,
          mutedColor: mutedColor,
        ),
      ] else if (period == StatisticsPeriod.week) ...[
        _bucketSection(
          title: 'Daily Detail',
          subtitle: 'Total income per day this week',
          buckets: _dailyBuckets(periodIncomes),
          color: dailyColor,
          emptyText: emptyText,
          surfaceColor: surfaceColor,
          borderColor: borderColor,
          textColor: textColor,
          mutedColor: mutedColor,
        ),
      ] else if (period == StatisticsPeriod.year) ...[
        _bucketSection(
          title: 'Monthly Summary',
          subtitle: 'Total income per month this year',
          buckets: _monthlyBuckets(periodIncomes),
          color: incomeColor,
          emptyText: emptyText,
          surfaceColor: surfaceColor,
          borderColor: borderColor,
          textColor: textColor,
          mutedColor: mutedColor,
        ),
      ],
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
        ),
    ];
  }

  double _previousTotal(List<TransactionEntity> transactions) {
    final DateTime start;
    final DateTime end;
    switch (_period) {
      case StatisticsPeriod.week:
        final current = _range.weeks.firstWhere((week) => week.contains(_selectedDate));
        end = current.start;
        start = DateTime(end.year, end.month, end.day - 7);
        break;
      case StatisticsPeriod.month:
        end = _range.start;
        start = DateTime(end.year, end.month - 1, 1);
        break;
      case StatisticsPeriod.year:
        end = DateTime(_selectedDate.year, 1, 1);
        start = DateTime(_selectedDate.year - 1, 1, 1);
        break;
    }
    return transactions.where((t) => !t.date.isBefore(start) && t.date.isBefore(end))
        .fold<double>(0, (sum, t) => sum + t.amount);
  }

  Widget _totalCard({
    required String title,
    required double value,
    required double previous,
  }) {
    return Card(
      elevation: 0,
      color: StatisticsDesign.primary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFFA7F3D0),
            )),
            const SizedBox(height: 8),
            Text(_fmt(value), style: const TextStyle(
              fontSize: 28, fontWeight: FontWeight.w700, color: Colors.white,
            )),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: const Color(0xFFA7F3D0), borderRadius: BorderRadius.circular(20)),
              child: Text(
                previous > 0
                    ? '${value >= previous ? '+' : ''}${((value - previous) / previous * 100).toStringAsFixed(1)}% vs previous ${_period.name}'
                    : 'No previous ${_period.name} data',
                style: const TextStyle(color: Color(0xFF082E22), fontSize: 12, fontWeight: FontWeight.w600),
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
    final double maxTotal = buckets.isEmpty
        ? 0.0
        : buckets.map((b) => b.total).reduce((a, b) => a > b ? a : b);

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
            if (buckets.isNotEmpty && title != 'Daily Detail') ...[
              SizedBox(
                height: 110,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final bucket in buckets)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              FittedBox(child: Text(_fmt(bucket.total), style: TextStyle(fontSize: 10, color: mutedColor))),
                              const SizedBox(height: 4),
                              SizedBox(
                                height: 70,
                                child: FractionallySizedBox(
                                  heightFactor: maxTotal > 0
                                      ? (bucket.total / maxTotal).clamp(0.0, 1.0)
                                      : 0,
                                  alignment: Alignment.bottomCenter,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: bucket.total == maxTotal
                                          ? StatisticsDesign.primary
                                          : StatisticsDesign.primary.withOpacity(0.35),
                                      borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              FittedBox(child: Text(
                                bucket.label.startsWith('Week ')
                                    ? bucket.label.split('  ·').first.replaceFirst('Week ', 'W')
                                    : bucket.label.substring(0, 3),
                                style: TextStyle(fontSize: 10, color: mutedColor),
                              )),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
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
                final double factor =
                    maxTotal > 0 ? (b.total / maxTotal).clamp(0.0, 1.0) : 0.0;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (idx > 0)
                      Divider(color: borderColor, height: 16, thickness: 1),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
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
                          const SizedBox(height: 6),
                          Container(
                            height: 6,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: borderColor.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            alignment: Alignment.centerLeft,
                            child: FractionallySizedBox(
                              widthFactor: factor,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: color,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
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
            CategoryPieChart(data: data, colorFor: _categoryColor),
            const SizedBox(height: 12),
            Divider(color: borderColor),
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
                          // The glyph used to be drawn in `color` on a 14%
                          // tint of that same colour: 1.74:1 for Allowance,
                          // 1.91:1 for Food, so the icon was the one thing in
                          // the row you could not see. A darker shade of the
                          // category colour keeps the identity and clears 5:1.
                          child: Icon(
                            _categoryIcon(e.key),
                            size: 18,
                            color: StatisticsDesign.legibleIconColor(color),
                          ),
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

  List<_Bucket> _monthlyBuckets(List<TransactionEntity> txns) {
    final List<_Bucket> buckets = <_Bucket>[];
    for (int m = 1; m <= 12; m++) {
      final MonthRange mRange = MonthRange.of(DateTime(_selectedDate.year, m, 1));
      double total = 0;
      bool any = false;
      for (final TransactionEntity t in txns) {
        if (!mRange.contains(t.date)) continue;
        total += t.amount;
        any = true;
      }
      if (!any) continue;

      buckets.add(_Bucket(
        DateFormat('MMMM yyyy').format(mRange.start),
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
      case 'coffee shop':
        return const Color(0xFFF59E0B);
      case 'other needs':
        return const Color(0xFF3B82F6);
      case 'data/internet package':
        return const Color(0xFF8B5CF6);
      case 'fuel':
        return const Color(0xFF0EA5E9);
      case 'salary':
        return const Color(0xFF10B981);
      case 'freelance':
        return const Color(0xFF14B8A6);
      case 'investment':
        return const Color(0xFF6366F1);
      case 'allowance':
      case 'pocket money':
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
      case 'coffee shop':
        return Icons.local_cafe_outlined;
      case 'fuel':
        return Icons.local_gas_station_outlined;
      case 'pocket money':
        return Icons.account_balance_wallet_outlined;
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
