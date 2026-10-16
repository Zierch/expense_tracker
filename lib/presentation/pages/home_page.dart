import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
    final startOfMonth = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
    final endOfMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0, 23, 59, 59);
    
    final transactionsAsync = ref.watch(transactionsStreamProvider);
    final summaryAsync = ref.watch(summaryProvider(start: startOfMonth, end: endOfMonth));

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
      body: Column(
        children: [
          SummaryCard(summaryAsync: summaryAsync),
          Expanded(
            child: transactionsAsync.when(
              data: (transactions) {
                final filtered = transactions.where((t) {
                  return t.date.isAfter(startOfMonth.subtract(const Duration(days: 1))) &&
                         t.date.isBefore(endOfMonth.add(const Duration(days: 1)));
                }).toList()
                  ..sort((a, b) => b.date.compareTo(a.date));

                if (filtered.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.receipt_long, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text('No transactions yet', style: TextStyle(fontSize: 18, color: Colors.grey)),
                        Text('Add your first transaction', style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
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
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/add'),
        icon: const Icon(Icons.add),
        label: const Text('Transaction'),
      ),
    );
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