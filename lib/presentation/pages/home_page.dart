import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:expense_tracker/domain/entities/month_range.dart';
import 'package:expense_tracker/domain/entities/summary_result.dart';
import 'package:expense_tracker/domain/entities/transaction_entity.dart';
import 'package:expense_tracker/presentation/providers/balance_visibility_provider.dart';
import 'package:expense_tracker/presentation/providers/providers.dart';
import 'package:expense_tracker/presentation/widgets/month_selector.dart';
import 'package:expense_tracker/presentation/widgets/transaction_tile.dart';

/// Semantic design tokens matching DESIGN.md for the Home dashboard.
abstract final class _HomeDesign {
  // Brand colors
  static const Color primary = Color(0xFF0E5A44);
  static const Color accentLight = Color(0xFFA7F3D0);

  // Light theme tokens
  static const Color lightText = Color(0xFF111827);
  static const Color lightMuted = Color(0xFF6B7280);

  /// The activity card's fill and edge in light mode.
  ///
  /// `light-activity` used to be `#E8F5E9` against a `#F4F6F8` background, which is a
  /// contrast ratio of 1.04: the card was a tint you had to look for. These two are
  /// the same hue, far enough apart to read as a card edge (fill 1.12 against the
  /// background, border 1.45) while staying the pale green of the design. Dark mode
  /// never had the problem — its tint is 1.63 against its own background.
  static const Color lightActivity = Color(0xFFD2F0DC);
  static const Color lightActivityBorder = Color(0xFFAFD8C0);

  // Dark theme tokens
  static const Color darkTinted = Color(0xFF244239);
  static const Color darkText = Color(0xFFEDF7F1);
  static const Color darkMuted = Color(0xFFA8BDB3);
  static const Color darkBorder = Color(0xFF31443A);
  static const Color darkAccent = Color(0xFF83DFB7);
  static const Color darkOnAccent = Color(0xFF10291F);
  static const Color darkError = Color(0xFFFF8A8A);

  // Spacing
  static const double spacingSmall = 8.0;
  static const double spacingScreen = 20.0;
  static const double spacingLarge = 24.0;

  // Corner radii
  static const double radiusButton = 14.0;
  static const double radiusActivity = 18.0;
  static const double radiusHero = 24.0;

  // Bundled mascot assets
  static const String piggyBankAsset = 'assets/images/piggy_bank.png';
  static const String receiptMascotAsset = 'assets/images/receipt_mascot.png';
}

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  DateTime _selectedMonth = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final MonthRange range = MonthRange.of(_selectedMonth);
    final transactionsAsync = ref.watch(transactionsStreamProvider);
    final summaryAsync =
        ref.watch(summaryProvider(start: range.start, end: range.end));

    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Expense Tracker',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        automaticallyImplyLeading: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: MonthSelector(
                month: _selectedMonth,
                onChanged: _selectMonth,
              ),
            ),
            SliverToBoxAdapter(
              child: HomeBalanceCard(summaryAsync: summaryAsync),
            ),
            SliverToBoxAdapter(
              child: HomeActivityCard(
                onAdd: () => context.push('/add'),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  _HomeDesign.spacingScreen,
                  _HomeDesign.spacingLarge,
                  _HomeDesign.spacingScreen,
                  _HomeDesign.spacingSmall,
                ),
                child: Text(
                  'Recent Transactions',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? _HomeDesign.darkText
                        : _HomeDesign.lightText,
                  ),
                ),
              ),
            ),
            transactionsAsync.when(
              data: (transactions) {
                final filtered = transactions
                    .where((t) => range.contains(t.date))
                    .toList()
                  ..sort(newestFirst);

                if (filtered.isEmpty) {
                  return SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.receipt_long,
                            size: 64,
                            color: isDark
                                ? _HomeDesign.darkMuted
                                : _HomeDesign.lightMuted,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No transactions yet',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? _HomeDesign.darkMuted
                                  : _HomeDesign.lightMuted,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Add your first transaction',
                            style: TextStyle(
                              color: isDark
                                  ? _HomeDesign.darkMuted
                                  : _HomeDesign.lightMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return SliverPadding(
                  // Bottom padding only as air under the last row. The 88 here used
                  // to be room for the floating add button, which the shell's bottom
                  // navigation replaced: the button is gone, so the gap was pushing
                  // the list up for nothing.
                  padding: const EdgeInsets.fromLTRB(
                    _HomeDesign.spacingScreen,
                    0,
                    _HomeDesign.spacingScreen,
                    _HomeDesign.spacingSmall,
                  ),
                  sliver: SliverList.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: _HomeDesign.spacingSmall),
                    itemBuilder: (context, index) {
                      final transaction = filtered[index];
                      return TransactionTile(
                        transaction: transaction,
                        onTap: () => context.push('/edit/${transaction.id}'),
                        onDelete: () => _deleteTransaction(transaction.id),
                      );
                    },
                  ),
                );
              },
              loading: () => const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text('Error: $e')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _refresh() async {
    final MonthRange range = MonthRange.of(_selectedMonth);

    ref.invalidate(transactionsStreamProvider);
    ref.invalidate(summaryProvider(start: range.start, end: range.end));

    try {
      await Future.wait(<Future<Object?>>[
        ref.read(transactionsStreamProvider.future),
        ref.read(summaryProvider(start: range.start, end: range.end).future),
      ], eagerError: true);
    } catch (error) {
      debugPrint('Dashboard refresh failed: $error');
    }
  }

  void _selectMonth(DateTime month) {
    setState(() => _selectedMonth = month);
  }

  Future<void> _deleteTransaction(int id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Transaction'),
        content: const Text('Are you sure you want to delete this transaction?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await ref.read(deleteTransactionUseCaseProvider).call(id);
    }
  }
}

/// Redesigned balance card with emerald theme and bundled piggy bank mascot.
class HomeBalanceCard extends ConsumerWidget {
  final AsyncValue<SummaryResult> summaryAsync;

  const HomeBalanceCard({super.key, required this.summaryAsync});

  static const String _hiddenBalance = 'Rp ••••••';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool balanceVisible = ref.watch(balanceVisibleProvider);

    return summaryAsync.when(
      data: (summary) => Container(
        margin: const EdgeInsets.symmetric(
          horizontal: _HomeDesign.spacingScreen,
          vertical: _HomeDesign.spacingSmall,
        ),
        padding: const EdgeInsets.all(_HomeDesign.spacingScreen),
        decoration: BoxDecoration(
          color: _HomeDesign.primary,
          borderRadius: BorderRadius.circular(_HomeDesign.radiusHero),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.18),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Total Balance',
                            style: TextStyle(
                              color: _HomeDesign.accentLight,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            onPressed: () => ref
                                .read(balanceVisibleProvider.notifier)
                                .toggle(),
                            icon: Icon(
                              balanceVisible
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            iconSize: 18,
                            color: _HomeDesign.accentLight,
                            tooltip: balanceVisible
                                ? 'Hide balance'
                                : 'Show balance',
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          balanceVisible
                              ? _formatCurrency(summary.balance)
                              : _hiddenBalance,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Semantics(
                  label: 'Piggy bank mascot',
                  child: Image.asset(
                    _HomeDesign.piggyBankAsset,
                    height: 64,
                    width: 96,
                    fit: BoxFit.contain,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _BalanceStatItem(
                      label: 'Income',
                      value: _formatCurrency(summary.totalIncome),
                      icon: Icons.south_west_rounded,
                      iconColor: _HomeDesign.accentLight,
                    ),
                  ),
                  Container(
                    height: 28,
                    width: 1,
                    color: Colors.white.withOpacity(0.15),
                  ),
                  Expanded(
                    child: _BalanceStatItem(
                      label: 'Expense',
                      value: _formatCurrency(summary.totalExpense),
                      icon: Icons.north_east_rounded,
                      iconColor: _HomeDesign.darkError,
                      alignEnd: true,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      loading: () => Container(
        margin: const EdgeInsets.symmetric(
          horizontal: _HomeDesign.spacingScreen,
          vertical: _HomeDesign.spacingSmall,
        ),
        height: 160,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(_HomeDesign.radiusHero),
        ),
        child: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Container(
        margin: const EdgeInsets.symmetric(
          horizontal: _HomeDesign.spacingScreen,
          vertical: _HomeDesign.spacingSmall,
        ),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(_HomeDesign.radiusHero),
        ),
        child: Text(
          'Error: $e',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onErrorContainer,
          ),
        ),
      ),
    );
  }

  String _formatCurrency(double amount) {
    return NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    ).format(amount);
  }
}

class _BalanceStatItem extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color iconColor;
  final bool alignEnd;

  const _BalanceStatItem({
    required this.label,
    required this.value,
    required this.icon,
    required this.iconColor,
    this.alignEnd = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: iconColor),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.85),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

/// Redesigned activity card with receipt mascot and quick Add action.
class HomeActivityCard extends StatelessWidget {
  final VoidCallback onAdd;

  const HomeActivityCard({super.key, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bgColor =
        isDark ? _HomeDesign.darkTinted : _HomeDesign.lightActivity;
    final Color borderColor = isDark
        ? _HomeDesign.darkBorder
        : _HomeDesign.lightActivityBorder;
    final Color textColor =
        isDark ? _HomeDesign.darkText : _HomeDesign.lightText;

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: _HomeDesign.spacingScreen,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(_HomeDesign.radiusActivity),
        border: Border.all(color: borderColor),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(_HomeDesign.radiusActivity),
          onTap: onAdd,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Semantics(
                  label: 'Receipt mascot',
                  child: Image.asset(
                    _HomeDesign.receiptMascotAsset,
                    width: 48,
                    height: 48,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Every little entry counts.',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: textColor,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text(
                    'Add',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: isDark
                        ? _HomeDesign.darkAccent
                        : _HomeDesign.primary,
                    foregroundColor: isDark
                        ? _HomeDesign.darkOnAccent
                        : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(_HomeDesign.radiusButton),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    minimumSize: const Size(48, 40),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
