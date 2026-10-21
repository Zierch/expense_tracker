// What the app remembers about a Google sign-in, and what it does with it.
//
// The memory is not a cache of the account — that stays the SDK's to keep. It
// answers one question: has this device signed in, so that asking the SDK to
// restore a session could be answered "yes"? On Android that question is not
// free: the restore call falls back to an interactive account sheet when it has
// nothing to auto-select (`google_sign_in_android`), so asking on behalf of a
// device that never signed in means putting a sign-in sheet in front of the
// user, unasked, at every launch.
//
// The decision around the SDK call is here rather than in the service because
// the call needs the platform SDK and the decision does not. What the service
// keeps — the account, the stream of auth events — is pinned nowhere: it cannot
// be reached from `flutter test` without a device.

import 'package:expense_tracker/data/services/google_sign_in_memory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // A fresh store per test, and the flag explicitly cleared: each test has to
  // start from a device that has never signed in, whatever the previous one left
  // behind.
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await const GoogleSignInMemory().forget();
  });

  group('GoogleSignInMemory', () {
    test('a device that has never signed in is not remembered', () async {
      expect(await const GoogleSignInMemory().hasSignedIn(), isFalse);
    });

    test('a sign-in is remembered, and a sign-out is not', () async {
      const GoogleSignInMemory memory = GoogleSignInMemory();

      await memory.remember();
      expect(await memory.hasSignedIn(), isTrue);

      await memory.forget();
      expect(await memory.hasSignedIn(), isFalse);
    });

    test('the flag outlives the instance, as it outlives a launch', () async {
      await const GoogleSignInMemory().remember();

      expect(await const GoogleSignInMemory().hasSignedIn(), isTrue,
          reason: 'a memory that only lives as long as the object would be '
              'forgotten every time the app is reopened, which is the whole '
              'point of storing it');
    });
  });

  group('restoreRememberedSignIn', () {
    test('does not ask at all when nothing is remembered', () async {
      int attempts = 0;

      await restoreRememberedSignIn(const GoogleSignInMemory(), () async {
        attempts++;
        return false;
      });

      expect(attempts, 0,
          reason: 'this is the fix: the SDK is never asked to find a session on '
              'a device that has never had one, so no account sheet can appear');
    });

    test('asks once a sign-in is remembered, and keeps remembering it', () async {
      const GoogleSignInMemory memory = GoogleSignInMemory();
      await memory.remember();
      int attempts = 0;

      await restoreRememberedSignIn(memory, () async {
        attempts++;
        return true;
      });

      expect(attempts, 1);
      expect(await memory.hasSignedIn(), isTrue);
    });

    test('forgets a session the SDK does not have', () async {
      const GoogleSignInMemory memory = GoogleSignInMemory();
      await memory.remember();

      await restoreRememberedSignIn(memory, () async => false);

      expect(await memory.hasSignedIn(), isFalse,
          reason: 'the SDK has nothing to restore, so a later launch must not '
              'ask again on the strength of this flag');
    });

    test('a declined sheet is not put in front of the user again', () async {
      const GoogleSignInMemory memory = GoogleSignInMemory();
      await memory.remember();

      await restoreRememberedSignIn(
        memory,
        () async => throw const GoogleSignInException(
          code: GoogleSignInExceptionCode.canceled,
        ),
      );

      expect(await memory.hasSignedIn(), isFalse);
    });

    test('an attempt that could not be judged keeps the memory', () async {
      const GoogleSignInMemory memory = GoogleSignInMemory();
      await memory.remember();

      await restoreRememberedSignIn(
        memory,
        () async => throw const GoogleSignInException(
          code: GoogleSignInExceptionCode.interrupted,
        ),
      );

      expect(await memory.hasSignedIn(), isTrue,
          reason: 'a failed attempt is not a sign-out: forgetting here would '
              'make a device with no connection at launch look like a device '
              'that has never signed in');
    });

    test('an unknown failure keeps it too', () async {
      const GoogleSignInMemory memory = GoogleSignInMemory();
      await memory.remember();

      await restoreRememberedSignIn(
        memory,
        () async => throw StateError('boom'),
      );

      expect(await memory.hasSignedIn(), isTrue);
    });
  });
}