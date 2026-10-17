import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:expense_tracker/domain/entities/month_range.dart';
import 'package:expense_tracker/presentation/providers/providers.dart';
import 'package:expense_tracker/presentation/widgets/transaction_tile.dart';
import 'package:expense_tracker/presentation/widgets/summary_card.dart';
import 'package:go_router/go_router.dart';

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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Expense Tracker'),
        actions: [
          IconButton(
            icon: const Icon(Icons.analytics_outlined),
            onPressed: () => context.push('/statistics'),
            tooltip: 'Statistics',
          ),
          IconButton(
            icon: const Icon(Icons.calendar_month),
            onPressed: _pickMonth,
            tooltip: 'Select Month',
          ),
          IconButton(
            icon: const Icon(Icons.cloud_upload_outlined),
            onPressed: () => context.push('/backup'),
            tooltip: 'Backup to Google Drive',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          // Always scrollable, so the pull also arms while the list is short,
          // empty or showing an error.
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: SummaryCard(summaryAsync: summaryAsync)),
            transactionsAsync.when(
              data: (transactions) {
                // Same predicate as the summary card above and the statistics
                // page. The hand-written range that used to live here pulled in
                // the previous month's last day and the next month's first day, so
                // the rows on screen did not add up to the total above them.
                final filtered = transactions
                    .where((t) => range.contains(t.date))
                    .toList()
                  ..sort((a, b) => b.date.compareTo(a.date));

                if (filtered.isEmpty) {
                  return const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.receipt_long, size: 64, color: Colors.grey),
                          SizedBox(height: 16),
                          Text('No transactions yet',
                              style: TextStyle(fontSize: 18, color: Colors.grey)),
                          Text('Add your first transaction',
                              style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    ),
                  );
                }

                return SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverList.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/add'),
        icon: const Icon(Icons.add),
        label: const Text('Transaction'),
      ),
    );
  }

  /// Re-runs the queries behind the month on screen.
  ///
  /// The card and the list describe the same snapshot, so both providers are
  /// dropped together; awaiting the new values keeps the indicator spinning
  /// until the screen actually shows them.
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
      // A provider-level failure already surfaces through the error branch
      // below; an unexpected throw (a provider disposed mid-refresh, say) would
      // otherwise vanish without a trace. The indicator retracts either way.
      debugPrint('Dashboard refresh failed: $error');
    }
  }

  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedMonth,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      helpText: 'SELECT MONTH',
      fieldHintText: 'Month/Year',
      fieldLabelText: 'Month',
      initialDatePickerMode: DatePickerMode.year,
    );
    if (picked != null) {
      setState(() => _selectedMonth = picked);
    }
  }

  Future<void> _deleteTransaction(int id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Transaction'),
        content: const Text('Are you sure you want to delete this transaction?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await ref.read(deleteTransactionUseCaseProvider).call(id);
    }
  }
}