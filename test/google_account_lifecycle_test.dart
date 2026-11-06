import 'dart:async';

import 'package:expense_tracker/data/services/google_drive_service.dart';
import 'package:expense_tracker/data/services/google_sign_in_memory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class _FakeClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(const Stream<List<int>>.empty(), 200);
  }
}

class _FakeGoogleSignInAccount implements GoogleSignInAccount {
  _FakeGoogleSignInAccount({
    this.email = 'user@example.com',
    this.displayName = 'User Name',
    this.id = 'fake-user-id',
    this.photoUrl,
  });

  @override
  final String email;

  @override
  final String? displayName;

  @override
  final String id;

  @override
  final String? photoUrl;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeGoogleSignIn implements GoogleSignIn {
  bool initialized = false;
  int attemptLightweightAuthenticationCalls = 0;
  bool throwOnSignOut = false;
  bool throwOnDisconnect = false;
  bool throwOnInitialize = false;

  final StreamController<GoogleSignInAuthenticationEvent> _events =
      StreamController<GoogleSignInAuthenticationEvent>.broadcast();

  @override
  Future<void> initialize({
    String? clientId,
    String? serverClientId,
    String? nonce,
    String? hostedDomain,
  }) async {
    if (throwOnInitialize) {
      throw const GoogleSignInException(
        code: GoogleSignInExceptionCode.unknownError,
        description: 'Failed to initialize Google Sign-In',
      );
    }
    initialized = true;
  }

  @override
  Stream<GoogleSignInAuthenticationEvent> get authenticationEvents =>
      _events.stream;

  @override
  Future<GoogleSignInAccount?> attemptLightweightAuthentication({
    bool reportAllExceptions = false,
  }) async {
    attemptLightweightAuthenticationCalls++;
    return null;
  }

  @override
  Future<void> signOut() async {
    if (throwOnSignOut) {
      throw const GoogleSignInException(
        code: GoogleSignInExceptionCode.unknownError,
        description: 'Failed to sign out from Google',
      );
    }
  }

  @override
  Future<void> disconnect() async {
    if (throwOnDisconnect) {
      throw const GoogleSignInException(
        code: GoogleSignInExceptionCode.unknownError,
        description: 'Failed to disconnect from Google',
      );
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await const GoogleSignInMemory().forget();
  });

  group('Passive Google account lifecycle', () {
    test('accountChanges is passive and emits current account without calling initialize', () async {
      final _FakeGoogleSignIn fakeSignIn = _FakeGoogleSignIn();
      final _FakeGoogleSignInAccount fakeAccount = _FakeGoogleSignInAccount();
      final GoogleDriveService service = GoogleDriveService.forTesting(
        client: _FakeClient(),
        headers: () async => <String, String>{},
        googleSignIn: fakeSignIn,
        initialAccount: fakeAccount,
      );

      final List<GoogleSignInAccount?> emitted = <GoogleSignInAccount?>[];
      final StreamSubscription<GoogleSignInAccount?> sub =
          service.accountChanges().listen(emitted.add);

      await Future<void>.delayed(Duration.zero);

      expect(emitted, <GoogleSignInAccount?>[fakeAccount]);
      expect(fakeSignIn.initialized, isFalse);
      expect(fakeSignIn.attemptLightweightAuthenticationCalls, 0);

      await sub.cancel();
    });

    test('initialize does not auto-restore session from memory', () async {
      const GoogleSignInMemory memory = GoogleSignInMemory();
      await memory.remember();
      expect(await memory.hasSignedIn(), isTrue);

      final _FakeGoogleSignIn fakeSignIn = _FakeGoogleSignIn();
      final GoogleDriveService service = GoogleDriveService.forTesting(
        client: _FakeClient(),
        headers: () async => <String, String>{},
        googleSignIn: fakeSignIn,
        signInMemory: memory,
      );

      await service.initialize();

      expect(fakeSignIn.initialized, isTrue);
      expect(fakeSignIn.attemptLightweightAuthenticationCalls, 0);
      expect(service.currentAccount, isNull);
      expect(await memory.hasSignedIn(), isTrue);
    });

    test('signOut clears account and remembered sign-in on success', () async {
      const GoogleSignInMemory memory = GoogleSignInMemory();
      await memory.remember();

      final _FakeGoogleSignIn fakeSignIn = _FakeGoogleSignIn();
      final _FakeGoogleSignInAccount fakeAccount = _FakeGoogleSignInAccount();
      final GoogleDriveService service = GoogleDriveService.forTesting(
        client: _FakeClient(),
        headers: () async => <String, String>{},
        googleSignIn: fakeSignIn,
        signInMemory: memory,
        initialAccount: fakeAccount,
      );

      final List<GoogleSignInAccount?> emitted = <GoogleSignInAccount?>[];
      final StreamSubscription<GoogleSignInAccount?> sub =
          service.accountChanges().listen(emitted.add);

      await service.signOut();

      expect(service.currentAccount, isNull);
      expect(await memory.hasSignedIn(), isFalse);
      expect(emitted.last, isNull);

      await sub.cancel();
    });

    test('signOut clears account and remembered sign-in even when SDK throws error', () async {
      const GoogleSignInMemory memory = GoogleSignInMemory();
      await memory.remember();

      final _FakeGoogleSignIn fakeSignIn = _FakeGoogleSignIn()
        ..throwOnSignOut = true;
      final _FakeGoogleSignInAccount fakeAccount = _FakeGoogleSignInAccount();
      final GoogleDriveService service = GoogleDriveService.forTesting(
        client: _FakeClient(),
        headers: () async => <String, String>{},
        googleSignIn: fakeSignIn,
        signInMemory: memory,
        initialAccount: fakeAccount,
      );

      final List<GoogleSignInAccount?> emitted = <GoogleSignInAccount?>[];
      final StreamSubscription<GoogleSignInAccount?> sub =
          service.accountChanges().listen(emitted.add);

      await expectLater(
        service.signOut(),
        throwsA(isA<BackupException>()),
      );

      expect(service.currentAccount, isNull);
      expect(await memory.hasSignedIn(), isFalse);
      expect(emitted.last, isNull);

      await sub.cancel();
    });

    test('disconnect clears account and remembered sign-in on success', () async {
      const GoogleSignInMemory memory = GoogleSignInMemory();
      await memory.remember();

      final _FakeGoogleSignIn fakeSignIn = _FakeGoogleSignIn();
      final _FakeGoogleSignInAccount fakeAccount = _FakeGoogleSignInAccount();
      final GoogleDriveService service = GoogleDriveService.forTesting(
        client: _FakeClient(),
        headers: () async => <String, String>{},
        googleSignIn: fakeSignIn,
        signInMemory: memory,
        initialAccount: fakeAccount,
      );

      final List<GoogleSignInAccount?> emitted = <GoogleSignInAccount?>[];
      final StreamSubscription<GoogleSignInAccount?> sub =
          service.accountChanges().listen(emitted.add);

      await service.disconnect();

      expect(service.currentAccount, isNull);
      expect(await memory.hasSignedIn(), isFalse);
      expect(emitted.last, isNull);

      await sub.cancel();
    });

    test('disconnect clears account and memory even when SDK throws error and does not claim revoked', () async {
      const GoogleSignInMemory memory = GoogleSignInMemory();
      await memory.remember();

      final _FakeGoogleSignIn fakeSignIn = _FakeGoogleSignIn()
        ..throwOnDisconnect = true;
      final _FakeGoogleSignInAccount fakeAccount = _FakeGoogleSignInAccount();
      final GoogleDriveService service = GoogleDriveService.forTesting(
        client: _FakeClient(),
        headers: () async => <String, String>{},
        googleSignIn: fakeSignIn,
        signInMemory: memory,
        initialAccount: fakeAccount,
      );

      final List<GoogleSignInAccount?> emitted = <GoogleSignInAccount?>[];
      final StreamSubscription<GoogleSignInAccount?> sub =
          service.accountChanges().listen(emitted.add);

      await expectLater(
        service.disconnect(),
        throwsA(
          isA<BackupException>().having(
            (BackupException e) => e.message,
            'message',
            allOf(
              contains('may still be live'),
              isNot(contains('revoked')),
              contains('https://myaccount.google.com/permissions'),
            ),
          ),
        ),
      );

      expect(service.currentAccount, isNull);
      expect(await memory.hasSignedIn(), isFalse);
      expect(emitted.last, isNull);

      await sub.cancel();
    });

    test('signOut clears account and remembered sign-in even when initialize throws error', () async {
      const GoogleSignInMemory memory = GoogleSignInMemory();
      await memory.remember();

      final _FakeGoogleSignIn fakeSignIn = _FakeGoogleSignIn()
        ..throwOnInitialize = true;
      final _FakeGoogleSignInAccount fakeAccount = _FakeGoogleSignInAccount();
      final GoogleDriveService service = GoogleDriveService.forTesting(
        client: _FakeClient(),
        headers: () async => <String, String>{},
        googleSignIn: fakeSignIn,
        signInMemory: memory,
        initialAccount: fakeAccount,
      );

      final List<GoogleSignInAccount?> emitted = <GoogleSignInAccount?>[];
      final StreamSubscription<GoogleSignInAccount?> sub =
          service.accountChanges().listen(emitted.add);

      await expectLater(
        service.signOut(),
        throwsA(isA<BackupException>()),
      );

      expect(service.currentAccount, isNull);
      expect(await memory.hasSignedIn(), isFalse);
      expect(emitted.last, isNull);

      await sub.cancel();
    });

    test('disconnect clears account and memory even when initialize throws error', () async {
      const GoogleSignInMemory memory = GoogleSignInMemory();
      await memory.remember();

      final _FakeGoogleSignIn fakeSignIn = _FakeGoogleSignIn()
        ..throwOnInitialize = true;
      final _FakeGoogleSignInAccount fakeAccount = _FakeGoogleSignInAccount();
      final GoogleDriveService service = GoogleDriveService.forTesting(
        client: _FakeClient(),
        headers: () async => <String, String>{},
        googleSignIn: fakeSignIn,
        signInMemory: memory,
        initialAccount: fakeAccount,
      );

      final List<GoogleSignInAccount?> emitted = <GoogleSignInAccount?>[];
      final StreamSubscription<GoogleSignInAccount?> sub =
          service.accountChanges().listen(emitted.add);

      await expectLater(
        service.disconnect(),
        throwsA(
          isA<BackupException>().having(
            (BackupException e) => e.message,
            'message',
            allOf(
              contains('may still be live'),
              isNot(contains('revoked')),
              contains('https://myaccount.google.com/permissions'),
            ),
          ),
        ),
      );

      expect(service.currentAccount, isNull);
      expect(await memory.hasSignedIn(), isFalse);
      expect(emitted.last, isNull);

      await sub.cancel();
    });
  });
}
