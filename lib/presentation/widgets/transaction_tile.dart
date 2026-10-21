import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:expense_tracker/domain/entities/transaction_entity.dart';

class TransactionTile extends StatelessWidget {
  final TransactionEntity transaction;
  final VoidCallback onTap;

  /// Asks the user to confirm and, only on confirmation, deletes the row.
  ///
  /// A `void` callback on purpose: the tile never completes a dismissal of its own. It
  /// answers `false` from `confirmDismiss` in every case — cancel, and after a successful
  /// delete — leaving the row stream the only thing that decides what the list contains.
  /// Letting the dismissal complete is what lost a cancelled row: `onDismissed` had
  /// already taken the tile out of the list, with nothing left to put it back.
  final VoidCallback onDelete;

  const TransactionTile({
    super.key,
    required this.transaction,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isIncome = transaction.isIncome;
    final color = isIncome ? const Color(0xFF2E9E5B) : const Color(0xFFD64545);
    final sign = isIncome ? '+' : '-';
    final name = transaction.displayCategory;

    return Dismissible(
      key: ValueKey(transaction.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: const Color(0xFFD64545),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      // Confirming happens in `confirmDismiss`, not `onDismissed`. `onDismissed` means
      // the tile has already been taken out of the list, so cancelling the dialog inside
      // it had nothing left to restore the row with: it disappeared until the app was
      // restarted. Here the answer is `false` either way — a cancelled delete springs the
      // tile back, and a confirmed one is dropped by the row stream once the write lands,
      // which keeps the stream the single source of truth for what the list contains.
      confirmDismiss: (_) async {
        onDelete();
        return false;
      },
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(_categoryIcon(name), color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (transaction.note != null && transaction.note!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        transaction.note!,
                        style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      DateFormat('dd MMM yyyy', 'en_US').format(transaction.date),
                      style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$sign${NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(transaction.amount)}',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _categoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'food':
        return Icons.restaurant;
      case 'other needs':
        return Icons.shopping_bag_outlined;
      case 'data/internet package':
        return Icons.wifi;
      case 'salary':
        return Icons.work_outline;
      case 'freelance':
        return Icons.laptop_mac;
      case 'investment':
        return Icons.trending_up;
      case 'allowance':
        return Icons.account_balance_wallet_outlined;
      case 'bonus':
        return Icons.card_giftcard;
      case 'gift':
        return Icons.redeem;
      default:
        return Icons.category_outlined;
    }
  }
}
