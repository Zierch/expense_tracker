import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:expense_tracker/domain/entities/transaction_entity.dart';

/// Semantic design tokens for transaction rows matching DESIGN.md.
/// The row's colours.
///
/// Public only so `color_contrast_test.dart` can measure the foreground/background
/// pairs the row really draws — a private class would force the test to restate
/// the hex values, which is the thing that let three of them drift below AA.
abstract final class TileDesign {
  // Surface & border
  static const Color lightSurface = Colors.white;

  /// Public, with the four text colours below, only so `color_contrast_test.dart`
  /// can measure the pairs the app actually draws. Nothing in the app reads them
  /// from here.
  static const Color darkSurface = Color(0xFF1B2924);
  static const Color lightBorder = Color(0xFFE5E7EB);
  static const Color darkBorder = Color(0xFF31443A);

  // Typography colors
  static const Color lightText = Color(0xFF111827);
  static const Color darkText = Color(0xFFEDF7F1);
  static const Color lightMuted = Color(0xFF6B7280);
  static const Color darkMuted = Color(0xFFA8BDB3);

  // Category icon backgrounds from DESIGN.md
  static const Color lightGrocery = Color(0xFFE4F1E9);
  static const Color darkGrocery = Color(0xFF29483B);
  static const Color lightIncome = Color(0xFFD1FAE5);
  static const Color darkIncome = Color(0xFF24473B);
  static const Color lightEntertainment = Color(0xFFEEF0F5);
  static const Color darkEntertainment = Color(0xFF353E4C);

  /// Food's own pair, and the reason it is not part of the grocery one.
  ///
  /// `_isGrocery` used to answer yes for `food`, so the commonest expense in the app
  /// was drawn in the grocery green — which is `#0E5A44` on `#83DFB7`, character for
  /// character the income pair. A row that spends money looked like a row that earned
  /// it, distinguished only by the glyph and the minus sign. Amber is the colour
  /// Statistics already gives Food in its pie chart, so the two screens agree.
  static const Color lightFood = Color(0xFFFEF3C7);
  static const Color darkFood = Color(0xFF3B2E18);
  static const Color foodIconLight = Color(0xFFB45309);
  static const Color foodIconDark = Color(0xFFFCD34D);

  // Category icon foregrounds (high WCAG AA/AAA contrast on respective backgrounds)
  static const Color groceryIconLight = Color(0xFF0E5A44);
  static const Color groceryIconDark = Color(0xFF83DFB7);
  static const Color entertainmentIconLight = Color(0xFF4338CA);
  static const Color entertainmentIconDark = Color(0xFFC7D2FE);
  static const Color incomeIconLight = Color(0xFF0E5A44);
  static const Color incomeIconDark = Color(0xFF83DFB7);

  // Fallback expense icon styling
  static const Color lightExpenseBg = Color(0xFFFDE8E8);
  static const Color darkExpenseBg = Color(0xFF3B2727);
  static const Color lightExpenseIcon = Color(0xFFD64545);
  static const Color darkExpenseIcon = Color(0xFFFF8A8A);

  // Amount text colors.
  //
  // The light pair used to be `#2E9E5B` and `#D64545`, which are 3.41:1 and
  // 4.38:1 on the white row — under AA for the 15px bold figure they colour.
  // Darkened to clear 4.5:1 with the hue intact. The same two values are what
  // Statistics draws its totals in, so the two screens stay in step.
  static const Color lightIncomeText = Color(0xFF24804A);
  static const Color darkIncomeText = Color(0xFF83DFB7);
  static const Color lightExpenseText = Color(0xFFC53030);
  static const Color darkExpenseText = Color(0xFFFF8A8A);
}

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

  /// Whether the row is a food expense, which is `Food` and the coffee it buys.
  ///
  /// Kept apart from [_isGrocery] because the two palettes used to be one, and that
  /// one was the income green.
  static bool _isFood(String category) {
    final lower = category.trim().toLowerCase();
    return lower == 'food' || lower == 'coffee shop';
  }

  static bool _isGrocery(String category) {
    final lower = category.trim().toLowerCase();
    return lower == 'grocery' ||
        lower == 'groceries' ||
        lower == 'supermarket' ||
        lower.contains('grocery') ||
        lower.contains('groceries');
  }

  static bool _isEntertainment(String category) {
    final lower = category.trim().toLowerCase();
    return lower == 'entertainment' ||
        lower == 'entertainments' ||
        lower == 'movie' ||
        lower == 'movies' ||
        lower == 'cinema' ||
        lower == 'game' ||
        lower == 'games' ||
        lower.contains('entertainment');
  }

  static IconData _categoryIcon(String category) {
    switch (category.trim().toLowerCase()) {
      case 'grocery':
      case 'groceries':
        return Icons.shopping_cart_outlined;
      case 'food':
        return Icons.restaurant;
      case 'coffee shop':
        return Icons.local_cafe_outlined;
      case 'fuel':
        return Icons.local_gas_station_outlined;
      case 'pocket money':
        return Icons.account_balance_wallet_outlined;
      case 'entertainment':
      case 'entertainments':
      case 'movie':
      case 'movies':
      case 'cinema':
        return Icons.movie_outlined;
      case 'game':
      case 'games':
        return Icons.sports_esports_outlined;
      case 'other needs':
        return Icons.shopping_bag_outlined;
      case 'data/internet package':
      case 'internet':
      case 'wifi':
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

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isIncome = transaction.isIncome;
    final String name = transaction.displayCategory;
    final String sign = isIncome ? '+' : '-';

    final Color surfaceColor = isDark ? TileDesign.darkSurface : TileDesign.lightSurface;
    final Color borderColor = isDark ? TileDesign.darkBorder : TileDesign.lightBorder;
    final Color titleColor = isDark ? TileDesign.darkText : TileDesign.lightText;
    final Color subtitleColor = isDark ? TileDesign.darkMuted : TileDesign.lightMuted;

    final Color iconBgColor;
    final Color iconColor;

    if (isIncome) {
      iconBgColor = isDark ? TileDesign.darkIncome : TileDesign.lightIncome;
      iconColor = isDark ? TileDesign.incomeIconDark : TileDesign.incomeIconLight;
    } else if (_isFood(name)) {
      iconBgColor = isDark ? TileDesign.darkFood : TileDesign.lightFood;
      iconColor = isDark ? TileDesign.foodIconDark : TileDesign.foodIconLight;
    } else if (_isGrocery(name)) {
      iconBgColor = isDark ? TileDesign.darkGrocery : TileDesign.lightGrocery;
      iconColor = isDark ? TileDesign.groceryIconDark : TileDesign.groceryIconLight;
    } else if (_isEntertainment(name)) {
      iconBgColor = isDark ? TileDesign.darkEntertainment : TileDesign.lightEntertainment;
      iconColor = isDark ? TileDesign.entertainmentIconDark : TileDesign.entertainmentIconLight;
    } else {
      iconBgColor = isDark ? TileDesign.darkExpenseBg : TileDesign.lightExpenseBg;
      iconColor = isDark ? TileDesign.darkExpenseIcon : TileDesign.lightExpenseIcon;
    }

    final Color amountColor = isIncome
        ? (isDark ? TileDesign.darkIncomeText : TileDesign.lightIncomeText)
        : (isDark ? TileDesign.darkExpenseText : TileDesign.lightExpenseText);

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
        child: const Icon(
          Icons.delete_outline,
          color: Colors.white,
          semanticLabel: 'Delete transaction',
        ),
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                key: const Key('transaction_tile_icon_container'),
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: iconBgColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _categoryIcon(name),
                  color: iconColor,
                  size: 22,
                  semanticLabel: name,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: titleColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (transaction.note != null && transaction.note!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        transaction.note!,
                        style: TextStyle(
                          fontSize: 13,
                          color: subtitleColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      DateFormat('dd MMM yyyy', 'en_US').format(transaction.date),
                      style: TextStyle(
                        fontSize: 12,
                        color: subtitleColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$sign${NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(transaction.amount)}',
                textAlign: TextAlign.end,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: amountColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
