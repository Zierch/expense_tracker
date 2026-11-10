// Colour that has to be readable, pinned by the ratio rather than by the hex.
//
// Three pairs in the app were below the contrast the rest of it holds itself to,
// and each was found by measuring rather than by looking: a grey-looking pie
// chart, an amount that was hard to read in light mode, and an icon drawn in the
// colour of its own background. A test that asserts a hex value would pin the
// shade; these assert the ratio, so a future palette change is free to pick any
// colour that still reads.
//
// WCAG AA: 4.5:1 for body text, 3:1 for large text and for graphical objects.

import 'dart:math' as math;

import 'package:expense_tracker/presentation/pages/statistics_page.dart';
import 'package:expense_tracker/presentation/widgets/transaction_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Relative luminance, as WCAG defines it.
double _luminance(Color color) {
  double channel(double c) =>
      c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}

/// The contrast ratio between two opaque colours, from 1 to 21.
double _contrast(Color a, Color b) {
  final double la = _luminance(a);
  final double lb = _luminance(b);
  final double hi = math.max(la, lb);
  final double lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// [foreground] laid over [background] at [alpha], as `withOpacity` renders it.
Color _over(Color foreground, Color background, double alpha) => Color.from(
      alpha: 1,
      red: foreground.r * alpha + background.r * (1 - alpha),
      green: foreground.g * alpha + background.g * (1 - alpha),
      blue: foreground.b * alpha + background.b * (1 - alpha),
    );

const Color _white = Color(0xFFFFFFFF);

void main() {
  group('amount text in the light theme', () {
    // The row's figure is 15px bold, which is under the 18.66px that would let it
    // pass as large text — so it needs the body-text ratio, on the row's surface.
    test('income and expense clear 4.5:1 on a white row', () {
      expect(_contrast(TileDesign.lightIncomeText, _white),
          greaterThanOrEqualTo(4.5),
          reason: 'the light income figure used to sit at 3.41:1');
      expect(_contrast(TileDesign.lightExpenseText, _white),
          greaterThanOrEqualTo(4.5),
          reason: 'the light expense figure used to sit at 4.38:1');
    });

    test('the dark theme figures clear it on the dark row', () {
      expect(_contrast(TileDesign.darkIncomeText, TileDesign.darkSurface),
          greaterThanOrEqualTo(4.5));
      expect(_contrast(TileDesign.darkExpenseText, TileDesign.darkSurface),
          greaterThanOrEqualTo(4.5));
    });
  });

  group('a category icon on its own tint', () {
    // Statistics draws each category's icon on a 14% tint of that same colour.
    // Drawn in the colour itself, the two are 1.7-2.4:1 apart: the icon is the
    // one thing in the row you cannot see.
    const List<Color> palette = <Color>[
      Color(0xFFF59E0B), // Food
      Color(0xFF3B82F6), // Other Needs
      Color(0xFF8B5CF6), // Data/Internet
      Color(0xFF0EA5E9), // Fuel
      Color(0xFF10B981), // Salary
      Color(0xFF14B8A6), // Freelance
      Color(0xFF6366F1), // Investment
      Color(0xFFEAB308), // Allowance
      Color(0xFFEC4899), // Bonus / Gift
      Color(0xFF64748B), // default
    ];

    test('every category icon clears 3:1 on the tint behind it', () {
      for (final Color color in palette) {
        final Color tint = _over(color, _white, 0.14);
        final Color icon = StatisticsDesign.legibleIconColor(color);

        expect(_contrast(icon, tint), greaterThanOrEqualTo(3.0),
            reason: 'the icon for $color is a smudge on its own tint');
      }
    });

    test('the darkening is what gets most of them there', () {
      // Guards the fix rather than the values. Not every colour needs it — a dark
      // enough one already reads on its own tint — so this asserts the majority
      // rather than all, which is what makes it a check on the fix and not a
      // restatement of it.
      int needed = 0;
      for (final Color color in palette) {
        final Color tint = _over(color, _white, 0.14);
        if (_contrast(color, tint) < 3.0) needed++;
      }

      expect(needed, greaterThan(palette.length ~/ 2),
          reason: 'the palette got lighter; the darkening may no longer be needed');
    });

    test('darkening keeps the hue, so the legend still reads as a colour key', () {
      for (final Color color in palette) {
        final HSLColor before = HSLColor.fromColor(color);
        final HSLColor after =
            HSLColor.fromColor(StatisticsDesign.legibleIconColor(color));

        // Lowering HSL lightness nudges the computed hue by about a degree for
        // some colours; a real hue change would be tens of degrees.
        expect((after.hue - before.hue).abs(), lessThan(5.0),
            reason: '$color changed hue when it was darkened');
        expect(after.lightness, lessThan(before.lightness));
      }
    });
  });

  group('the statistics totals', () {
    test('the light income and expense figures clear 4.5:1 on a white card', () {
      expect(_contrast(StatisticsDesign.lightIncome, _white),
          greaterThanOrEqualTo(4.5));
      expect(_contrast(StatisticsDesign.lightExpense, _white),
          greaterThanOrEqualTo(4.5));
    });
  });
}
