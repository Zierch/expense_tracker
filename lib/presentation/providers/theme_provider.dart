// Which theme the app presents — the user's choice, kept between launches.
//
// `MaterialApp` already renders light and dark from `theme` and `darkTheme`, so
// the only state here is which of the three behaviours wins: follow the system,
// force light, force dark. The default is the system, which is exactly what the
// app did before this file existed — someone who never opens the picker cannot
// see the difference.
//
// The choice is stored by name rather than by `ThemeMode`'s index, so reordering
// or extending the enum later cannot quietly turn a stored "dark" into "light":
// an unknown name falls back to the system instead.
//
// `main()` loads `SharedPreferences` *before* `runApp` and overrides
// [sharedPreferencesProvider] with the instance. That is why the first frame is
// already painted in the remembered mode: an async read inside a provider build
// would have flashed the system theme for a fraction of a second on every launch.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The already-loaded [SharedPreferences] instance, provided by an override in
/// `main()`.
///
/// `null` means the read failed on startup: an unremembered theme is a
/// cosmetic regression and this provider stays `null` so the app still opens
/// — the never-ending splash of v1.2.0 is what this null path prevents.
final sharedPreferencesProvider = Provider<SharedPreferences?>((ref) => null);

/// The user's theme choice under one key.
class ThemeModeController extends Notifier<ThemeMode> {
  static const String _key = 'themeMode';

  @override
  ThemeMode build() {
    return switch (ref.watch(sharedPreferencesProvider)?.getString(_key)) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  /// Applies and remembers the mode.
  ///
  /// Without a backing store (startup read failed) the choice still applies
  /// for this session, it simply is not remembered for the next one. A failed
  /// write costs the same, so neither gates the visible change.
  void set(ThemeMode mode) {
    final SharedPreferences? prefs = ref.read(sharedPreferencesProvider);
    if (prefs != null) {
      unawaited(prefs.setString(_key, mode.name));
    }
    state = mode;
  }
}

final themeModeProvider =
    NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);
