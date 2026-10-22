// Whether the dashboard shows the month's balance figure or hides it.
//
// The card is on the first screen of the app, so the month's balance is readable
// by anyone the phone is handed to or held in front of. The eye on the balance
// row is for those moments; the choice is stored, so it does not have to be
// repeated on every launch.
//
// The stored key is a bool under `balanceVisible`, and a *missing* key means
// shown: someone who never touches the eye sees exactly what the app showed
// before this file existed. `SharedPreferences` arrives from `main()` through
// [sharedPreferencesProvider]; a null there (the startup read failed) means the
// choice applies for this session and is simply not remembered — the same
// trade-off the theme picker makes, and for the same reason.
//
// Only the balance is affected. Income and expense are deliberate entries the
// user just typed and are not in this provider's scope.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme_provider.dart';

/// Whether the balance on the dashboard is on screen.
class BalanceVisibilityController extends Notifier<bool> {
  static const String _key = 'balanceVisible';

  @override
  bool build() => ref.watch(sharedPreferencesProvider)?.getBool(_key) ?? true;

  /// Hides the balance, or shows it again.
  ///
  /// The new value is computed before the store is touched so the remembered
  /// value and the visible one cannot disagree, whether or not the write lands.
  void toggle() {
    final bool next = !state;
    final SharedPreferences? prefs = ref.read(sharedPreferencesProvider);
    if (prefs != null) {
      unawaited(prefs.setBool(_key, next));
    }
    state = next;
  }
}

final balanceVisibleProvider =
    NotifierProvider<BalanceVisibilityController, bool>(
  BalanceVisibilityController.new,
);