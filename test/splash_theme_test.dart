import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('night splash background uses the dark canvas color', () {
    final colors = File('android/app/src/main/res/values-night/colors.xml')
        .readAsStringSync();
    expect(colors, contains('<color name="splash_background">#101916</color>'));
    final styles = File('android/app/src/main/res/values-night-v31/styles.xml')
        .readAsStringSync();
    expect(styles, contains('@color/splash_background'));
  });
}
