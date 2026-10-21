// How an amount is typed: digits in, grouped text out.
//
// The value stays a plain number — what the field holds is that number with a
// '.' every three digits, so "400000" reads as "400.000" while it is being
// typed and the zeros can be counted at a glance instead of one by one.
//
// The "Rp." in front is the field's `prefixText`, which is decoration: it is
// not part of the value, it cannot be typed over, and no part of it can be
// deleted. Parsing therefore never has to strip it.

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// Digits, grouped as they arrive.
class IdrAmountInputFormatter extends TextInputFormatter {
  IdrAmountInputFormatter({this.maxDigits = defaultMaxDigits});

  /// 12 digits, so the largest amount is 999,999,999,999 — the ceiling the
  /// field had while it held ungrouped digits.
  static const int defaultMaxDigits = 12;

  final int maxDigits;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final String digits = idrDigitsOf(newValue.text);
    final String? grouped = formatIdrDigits(digits, maxDigits: maxDigits);

    // Past the ceiling the old text stands, rather than a number the user is
    // still typing being cut down to size.
    if (grouped == null) return oldValue;

    return TextEditingValue(
      text: grouped,
      // The caret follows the digit it was behind, not the old offset: grouping
      // inserts '.' and would otherwise walk the caret leftwards.
      selection: TextSelection.collapsed(
        offset: _caretAfter(grouped, _digitsBefore(newValue)),
      ),
    );
  }

  /// How many digits of [value] sit before its caret.
  static int _digitsBefore(TextEditingValue value) {
    final int caret = value.selection.baseOffset;
    if (caret <= 0) return 0;
    final String before =
        caret >= value.text.length ? value.text : value.text.substring(0, caret);
    return idrDigitsOf(before).length;
  }

  /// The offset in [grouped] just past its [digitIndex]-th digit.
  static int _caretAfter(String grouped, int digitIndex) {
    if (digitIndex <= 0) return 0;

    int seen = 0;
    for (int i = 0; i < grouped.length; i++) {
      if (_isDigit(grouped.codeUnitAt(i))) {
        seen++;
        if (seen == digitIndex) return i + 1;
      }
    }
    return grouped.length;
  }

  static bool _isDigit(int codeUnit) => codeUnit >= 0x30 && codeUnit <= 0x39;
}

/// Indonesian grouping, from `intl` — an already-installed dependency that
/// knows the separator, so it is not spelled out here.
final NumberFormat _idrGrouping = NumberFormat.decimalPattern('id_ID');

/// The digits of [text], with any grouping and anything else non-numeric gone.
String idrDigitsOf(String text) => text.replaceAll(RegExp(r'[^0-9]'), '');

/// [digits] as the field shows it, or `null` when it is past [maxDigits].
String? formatIdrDigits(
  String digits, {
  int maxDigits = IdrAmountInputFormatter.defaultMaxDigits,
}) {
  if (digits.length > maxDigits) return null;
  if (digits.isEmpty) return '';

  return _idrGrouping.format(int.parse(digits));
}

/// The amount [text] stands for, or `null` when it holds no digit at all.
double? parseIdrAmount(String text) {
  final String digits = idrDigitsOf(text);
  return digits.isEmpty ? null : double.tryParse(digits);
}

/// [amount] as the field shows it, for a value coming back from storage.
String formatIdrAmount(double amount) {
  final String digits = amount.toStringAsFixed(0);
  return formatIdrDigits(digits) ?? digits;
}