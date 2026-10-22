import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The navigation bar fix lives in Android theme XML, out of reach of the Dart
/// code, so it gets its own check: on Android 15+ the bar colour is ignored and
/// the system's contrast scrim lands on top of whatever is behind the bar. With
/// the scrim left on, a Xiaomi on Android 16 painted a light one over a dark
/// bar. Deleting these attributes from a theme would bring that back silently.
void main() {
  const Map<String, bool> themes = <String, bool>{
    'values': true,
    'values-v31': true,
    'values-night': false,
    'values-night-v31': false,
  };

  themes.forEach((String qualifier, bool light) {
    test('the $qualifier themes turn the contrast scrim off', () {
      final String xml = File(
        'android/app/src/main/res/$qualifier/styles.xml',
      ).readAsStringSync();

      // One per style, LaunchTheme and NormalTheme.
      expect(
        RegExp(
          r'<item name="android:enforceNavigationBarContrast">false</item>',
        ).allMatches(xml).length,
        2,
      );
      expect(
        RegExp(
          '<item name="android:windowLightNavigationBar">$light</item>',
        ).allMatches(xml).length,
        2,
      );
    });
  });
}