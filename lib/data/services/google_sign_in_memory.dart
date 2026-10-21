// What the app remembers about a Google sign-in, and what it does with that.
//
// The memory exists because asking the SDK to restore a session is not a silent
// question. `attemptLightweightAuthentication` is the only restore call left in
// google_sign_in 7, and on Android it first tries to select an account that has
// already authorised the app and then, when that finds nothing, an *interactive*
// account sheet (see `GoogleSignInAndroid.attemptLightweightAuthentication` in
// google_sign_in_android). An app that asks at every launch therefore asks users
// who never signed in to sign in, on a page they opened for something else.
//
// Remembering the sign-in is what makes the question askable: it is only asked
// where the answer could be "yes", and it stops being remembered as soon as the
// SDK says there is nothing to restore.

import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The app's own memory of "this device has signed in, and has not signed out
/// since".
///
/// Only the flag is kept. The account itself belongs to the SDK, which hands
/// back a fresh one on every restore or sign-in; the app storing a copy would
/// only be able to serve a stale one.
class GoogleSignInMemory {
  const GoogleSignInMemory();

  static const String _key = 'googleSignedInBefore';

  /// True when a session may be there to restore.
  ///
  /// A store that cannot be read answers `false`: an account sheet appearing
  /// unasked is worse than the sign-in button needing one tap, and that button
  /// is in front of the user either way.
  Future<bool> hasSignedIn() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_key) ?? false;
    } on Object {
      return false;
    }
  }

  /// Records a successful sign-in, so a later launch may restore it.
  ///
  /// A failed write is not fatal: the session works for this run either way,
  /// and the next launch simply signs in again.
  Future<void> remember() => _write(true);

  /// Drops the memory, because there is no session to restore, or because the
  /// user has signed out or revoked the access themselves.
  Future<void> forget() => _write(false);

  Future<void> _write(bool remembered) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, remembered);
    } on Object {
      // See remember(): nothing about this run depends on the write landing.
    }
  }
}

/// Restores a session the user granted earlier — and asks only where one could
/// exist.
///
/// [attempt] is the SDK call, passed in rather than reached for, because the
/// part that has to hold is the decision around it: ask only when a sign-in is
/// remembered, forget it when the SDK reports there is nothing, and keep it when
/// the attempt could not be judged. That decision is testable without a device,
/// which the SDK call itself is not.
///
/// The caller is expected to pass an attempt that reports a declined sheet as a
/// [GoogleSignInException] (`reportAllExceptions: true`) — otherwise a refusal
/// and a genuine "no session" arrive as the same `null`.
Future<void> restoreRememberedSignIn(
  GoogleSignInMemory memory,
  Future<bool> Function() attempt,
) async {
  if (!await memory.hasSignedIn()) return;

  try {
    if (await attempt()) return;

    // The SDK has no session for this device, so stop asking on every launch.
    await memory.forget();
  } on GoogleSignInException catch (error) {
    // A declined sheet is an answer: the user said no, so do not put it in front
    // of them again unasked.
    if (error.code == GoogleSignInExceptionCode.canceled) {
      await memory.forget();
      return;
    }
    // Anything else — interrupted, no suitable UI, no connection — is "could not
    // tell", so the memory stays and a later launch tries again.
  } on Object {
    // Same reasoning as above: an unknown failure must not erase the fact that
    // this device has signed in before.
  }
}