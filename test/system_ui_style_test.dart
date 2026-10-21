// The system bars follow this app's theme, not the device's. A light Android
// theme under an in-app dark theme left the navigation bar white — a strip of
// another app below the dark dashboard — because nothing in the app ever told it
// otherwise. These pin the colours, since neither the widget tests nor CI can see
// the window.

import 'package:expense_tracker/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dark theme: the bar matches the dark page, its icons go light', () {
    final SystemUiOverlayStyle style = systemUiStyleFor(Brightness.dark);

    expect(style.systemNavigationBarColor, const Color(0xFF0E1113));
    expect(style.systemNavigationBarIconBrightness, Brightness.light);
    expect(style.systemNavigationBarDividerColor, Colors.transparent);
  });

  test('light theme: the bar matches the light page, its icons stay dark', () {
    final SystemUiOverlayStyle style = systemUiStyleFor(Brightness.light);

    expect(style.systemNavigationBarColor, const Color(0xFFF4F6F8));
    expect(style.systemNavigationBarIconBrightness, Brightness.dark);
  });

  test('the two themes do not share a bar colour', () {
    expect(
      systemUiStyleFor(Brightness.dark).systemNavigationBarColor,
      isNot(systemUiStyleFor(Brightness.light).systemNavigationBarColor),
      reason: 'one colour for both themes is exactly the white strip this '
          'pins against: the bar was not following the app at all',
    );
  });
}
