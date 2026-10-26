import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import 'google_config.dart';
import 'google_sign_in_memory.dart';

/// A failure whose message is already phrased for the user.
class BackupException implements Exception {
  BackupException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Outcome of a successful archive upload.
class DriveUploadResult {
  DriveUploadResult({
    required this.fileName,
    required this.folderName,
    required this.replacedExisting,
    this.webViewLink,
  });

  final String fileName;
  final String folderName;

  /// True when a file with the same name already existed and was overwritten.
  final bool replacedExisting;

  final String? webViewLink;
}

/// One backup file sitting in the Drive archive folder.
class DriveBackupFile {
  DriveBackupFile({required this.id, required this.name, this.modifiedTime});

  final String id;
  final String name;

  /// When Drive last changed the file; null when it did not say.
  final DateTime? modifiedTime;
}

/// Signs the user in with Google and archives JSON backups in Google Drive.
///
/// Only the non-sensitive `drive.file` scope is requested, so the app can never
/// see anything in the user's Drive other than the files it created itself.
///
/// Deliberately a process-wide singleton: [_accountController] is a single
/// broadcast controller that is intentionally *never* closed. It lives exactly
/// as long as the app process, so there is no leak to plug — disposing it would
/// merely stop auth updates from reaching the UI.
class GoogleDriveService {
  GoogleDriveService._();

  static final GoogleDriveService instance = GoogleDriveService._();

  static const String _driveApi = 'https://www.googleapis.com/drive/v3';
  static const String _uploadApi = 'https://www.googleapis.com/upload/drive/v3';
  static const String _folderMime = 'application/vnd.google-apps.folder';
  static const String _jsonMime = 'application/json';
  static const List<String> _scopes = <String>[GoogleConfig.driveFileScope];

  /// Stops a request from hanging forever on a dead connection.
  static const Duration _requestTimeout = Duration(seconds: 60);

  /// How much of one file a restore will pull into memory. A month of
  /// transactions is tens of kilobytes; anything past this was not written by
  /// this app's export, and reading it would only cost memory.
  static const int _maxBackupBytes = 10 * 1024 * 1024;

  /// How many pages of a Drive listing to follow. Five pages of a hundred is
  /// five hundred months — more than a decade of daily use — and stopping is
  /// better than letting a listing that never ends hold the screen.
  static const int _maxListPages = 5;

  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  final StreamController<GoogleSignInAccount?> _accountController =
      StreamController<GoogleSignInAccount?>.broadcast();

  Future<void>? _initialization;
  StreamSubscription<GoogleSignInAuthenticationEvent>? _authSubscription;
  GoogleSignInAccount? _account;

  /// Whether this device has signed in before, so the SDK is only asked to
  /// restore a session where one could exist. See [restoreRememberedSignIn].
  final GoogleSignInMemory _signInMemory = const GoogleSignInMemory();

  bool get isConfigured => GoogleConfig.isConfigured;

  GoogleSignInAccount? get currentAccount => _account;

  /// Emits the current account straight away, then every change after that.
  Stream<GoogleSignInAccount?> accountChanges() async* {
    await initialize();
    yield _account;
    yield* _accountController.stream;
  }

  /// Prepares the Google Sign-In SDK. Safe to call more than once.
  ///
  /// A *failed* attempt is deliberately not cached: a transient problem (the
  /// device having no network yet, for example) must not permanently brick the
  /// backup page until the app is restarted.
  Future<void> initialize() async {
    final Future<void>? pending = _initialization;
    if (pending != null) return pending;

    final Future<void> attempt = _initialize();
    _initialization = attempt;

    try {
      await attempt;
    } on Object {
      if (identical(_initialization, attempt)) {
        _initialization = null;
      }
      rethrow;
    }
  }

  Future<void> _initialize() async {
    if (!isConfigured) {
      throw BackupException(
        'Google Client ID is not configured.\n\n'
        'Set GoogleConfig.serverClientId in '
        'lib/data/services/google_config.dart to a "Web application" client ID '
        'from the Google Cloud Console; the value ends in '
        '".apps.googleusercontent.com".',
      );
    }

    await _googleSignIn.initialize(serverClientId: GoogleConfig.serverClientId);

    // Cancel any previous listener so a retried initialization cannot end up
    // with two subscriptions feeding the same controller.
    final StreamSubscription<GoogleSignInAuthenticationEvent>? previous =
        _authSubscription;
    if (previous != null) {
      await previous.cancel();
    }

    _authSubscription = _googleSignIn.authenticationEvents.listen(
      (GoogleSignInAuthenticationEvent event) {
        _account = switch (event) {
          GoogleSignInAuthenticationEventSignIn() => event.user,
          GoogleSignInAuthenticationEventSignOut() => null,
        };
        _accountController.add(_account);
      },
      onError: (Object error) {
        _account = null;
        _accountController.addError(error);
      },
    );

    // `reportAllExceptions` is what tells a declined account sheet apart from a
    // device that has no session at all — the two are the same `null` without
    // it, and one of them has to be remembered differently. See
    // [restoreRememberedSignIn].
    await restoreRememberedSignIn(
      _signInMemory,
      () async {
        final GoogleSignInAccount? restored = await _googleSignIn
            .attemptLightweightAuthentication(reportAllExceptions: true);
        if (restored == null) return false;

        _account = restored;
        _accountController.add(restored);
        return true;
      },
    );
  }

  /// Opens the Google account picker and returns the signed-in account.
  Future<GoogleSignInAccount> signIn() async {
    await initialize();

    if (!_googleSignIn.supportsAuthenticate()) {
      throw BackupException('This device does not support Google Sign-In.');
    }

    try {
      final GoogleSignInAccount account = await _googleSignIn.authenticate();
      _account = account;
      _accountController.add(account);
      // From here on a launch may restore this session, and may therefore ask
      // the SDK to look for one.
      await _signInMemory.remember();
      return account;
    } on GoogleSignInException catch (error) {
      throw BackupException(_describeSignInError(error));
    }
  }

  /// Signs out. The previously granted Drive permission is deliberately kept,
  /// so signing in again does not ask for consent twice.
  Future<void> signOut() async {
    await initialize();
    try {
      await _googleSignIn.signOut();
    } on GoogleSignInException catch (error) {
      throw BackupException(_describeSignInError(error));
    }
    _account = null;
    // Signing out is the user's answer: no launch should try to restore it.
    await _signInMemory.forget();
  }

  /// Revokes this app's Drive authorisation, then signs out.
  ///
  /// [signOut] deliberately keeps the grant so that a later export does not ask
  /// for consent twice. This is the opposite: it withdraws the authorisation
  /// itself, so the next export shows Google's consent screen again.
  ///
  /// Files already exported are left where they are. Losing access is not the
  /// same as asking for the backups to be deleted, so nothing here removes
  /// them, and the UI must not imply otherwise.
  ///
  /// The SDK reports a sign-out *before* it attempts the revoke, so a failure
  /// here can leave the user signed out on this device while the grant is still
  /// live. The error therefore says so rather than reporting a bare failure, and
  /// points at Google's own page for withdrawing the access by hand.
  Future<void> disconnect() async {
    await initialize();
    try {
      await _googleSignIn.disconnect();
    } on GoogleSignInException catch (error) {
      throw BackupException(
        '${_describeSignInError(error)} You are now signed out on this '
        'device, but the access you granted may still be live. To withdraw it '
        'for certain, remove Expense Tracker at '
        'https://myaccount.google.com/permissions.',
      );
    }
    _account = null;
    await _signInMemory.forget();
  }

  /// True when the Drive scope was already granted for the signed-in account.
  Future<bool> hasDriveAccess() async {
    await initialize();
    final GoogleSignInAccount? account = _account;
    if (account == null) return false;
    try {
      final GoogleSignInClientAuthorization? authorization =
          await account.authorizationClient.authorizationForScopes(_scopes);
      return authorization != null;
    } on Object {
      return false;
    }
  }

  /// Uploads [data] as a pretty-printed JSON file.
  ///
  /// A file with the same name in the archive folder is replaced, so exporting
  /// the same month twice stays idempotent.
  Future<DriveUploadResult> uploadJson({
    required String fileName,
    required Map<String, dynamic> data,
    String? folderName,
  }) async {
    await initialize();
    final String folder = folderName ?? GoogleConfig.driveFolderName;
    await _ensureDriveAccess();

    final Uint8List bytes = Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(data)),
    );

    Map<String, String> headers = await _authorizationHeaders();
    final String folderId = await _findOrCreateFolder(headers, folder);
    final String? existingId = await _findFileId(headers, folderId, fileName);

    http.Response response = existingId == null
        ? await _createFile(headers, folderId, fileName, bytes)
        : await _replaceFileContent(headers, existingId, bytes);

    if (response.statusCode == 401) {
      // The cached access token expired. A genuine scope *denial* is already
      // rejected earlier by _ensureDriveAccess, so refreshing is the right move.
      headers = await _authorizationHeaders();
      response = existingId == null
          ? await _createFile(headers, folderId, fileName, bytes)
          : await _replaceFileContent(headers, existingId, bytes);
    }

    if (response.statusCode == 401) {
      throw BackupException(
        'Google Drive access is no longer valid. Sign out and sign in again '
        'to grant it afresh.',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw BackupException(
        'Upload to Google Drive failed (HTTP ${response.statusCode}).\n'
        '${_extractErrorMessage(response.body)}',
      );
    }

    final Map<String, dynamic> body =
        jsonDecode(response.body) as Map<String, dynamic>;

    return DriveUploadResult(
      fileName: body['name'] as String? ?? fileName,
      folderName: folder,
      replacedExisting: existingId != null,
      webViewLink: body['webViewLink'] as String?,
    );
  }

  // ---------------------------------------------------------------------------
  // Google Drive REST helpers
  // ---------------------------------------------------------------------------

  /// The backup files in the archive folder, newest name first.
  ///
  /// Reading never creates the folder: a Drive that has never been exported to
  /// should be answered with "there is nothing here", not with an empty folder
  /// made behind the user's back.
  Future<List<DriveBackupFile>> listBackupFiles({String? folderName}) async {
    await initialize();
    final String folder = folderName ?? GoogleConfig.driveFolderName;
    await _ensureDriveAccess();

    final Map<String, String> headers = await _authorizationHeaders();
    final String? folderId = await _findFolderId(headers, folder);
    if (folderId == null) return <DriveBackupFile>[];

    final String query = "'${_escapeQueryValue(folderId)}' in parents "
        "and name contains 'expense-tracker-' "
        "and mimeType = '$_jsonMime' and trashed = false";

    final List<Map<String, dynamic>> files = await _listFiles(
      headers,
      query,
      pageSize: 100,
      fields: 'files(id,name,modifiedTime)',
      orderBy: 'name desc',
    );

    return files
        .map((Map<String, dynamic> file) => DriveBackupFile(
              id: file['id'] as String,
              name: file['name'] as String? ?? '',
              modifiedTime:
                  DateTime.tryParse(file['modifiedTime'] as String? ?? ''),
            ))
        .where((DriveBackupFile file) => file.name.isNotEmpty)
        .toList();
  }

  /// The text of one stored backup.
  ///
  /// `alt=media` is what returns the file's bytes rather than its metadata.
  Future<String> downloadJson(String fileId) async {
    await initialize();
    await _ensureDriveAccess();

    final Uri uri =
        Uri.parse('$_driveApi/files/${Uri.encodeComponent(fileId)}?alt=media');
    return utf8.decode(await _downloadBytes(uri));
  }

  /// One file's bytes, refused past [_maxBackupBytes].
  ///
  /// Read as a stream rather than through `http.get`, which buffers whatever the
  /// server sends before the caller can look at it: the cap has to be applied
  /// while the bytes arrive, or a file far larger than a month of transactions is
  /// already in memory by the time it is refused.
  ///
  /// The client is created and closed here because the response stream outlives
  /// the request that started it — closing the client is what cancels a body
  /// that is no longer wanted, on the error paths as much as on the happy one.
  Future<Uint8List> _downloadBytes(Uri uri) async {
    final http.Client client = http.Client();
    try {
      Map<String, String> headers = await _authorizationHeaders();
      http.StreamedResponse response =
          await _sendStreamed(client, uri, headers);

      if (response.statusCode == 401) {
        // Same as the upload path: an expired access token is refreshed once,
        // and a genuine scope denial never reaches here — `_ensureDriveAccess`
        // rejects that earlier.
        headers = await _authorizationHeaders();
        response = await _sendStreamed(client, uri, headers);
        if (response.statusCode == 401) {
          throw BackupException(
            'Google Drive access is no longer valid. Sign out and sign in again '
            'to grant it afresh.',
          );
        }
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final String body = await response.stream.bytesToString();
        throw BackupException(
          'Could not read that backup from Google Drive '
          '(HTTP ${response.statusCode}).\n'
          '${_extractErrorMessage(body)}',
        );
      }

      // What the server declares, when it declares anything: refusing here saves
      // reading a single byte of a file that is already too big.
      final int? declared = response.contentLength;
      if (declared != null && declared > _maxBackupBytes) {
        throw _tooLargeToBeABackup();
      }

      final BytesBuilder collected = BytesBuilder(copy: false);
      await for (final List<int> chunk in response.stream) {
        collected.add(chunk);
        if (collected.length > _maxBackupBytes) {
          throw _tooLargeToBeABackup();
        }
      }

      return collected.takeBytes();
    } finally {
      client.close();
    }
  }

  BackupException _tooLargeToBeABackup() => BackupException(
        'That backup is larger than ${_maxBackupBytes ~/ (1024 * 1024)} MB, so '
        "it is not one of this app's month backups.",
      );

  Future<http.StreamedResponse> _sendStreamed(
    http.Client client,
    Uri uri,
    Map<String, String> headers,
  ) async {
    try {
      return await client
          .send(http.Request('GET', uri)..headers.addAll(headers))
          .timeout(_requestTimeout);
    } on TimeoutException {
      throw BackupException(
        'The connection to Google Drive timed out. Check your connection and try again.',
      );
    }
  }

  /// Makes sure the Drive scope is granted, requesting consent if needed.
  ///
  /// Must be triggered by a user action when
  /// `authorizationRequiresUserInteraction()` is true.
  Future<void> _ensureDriveAccess() async {
    final GoogleSignInAccount? account = _account;
    if (account == null) {
      throw BackupException('You are not signed in to a Google account.');
    }

    final GoogleSignInClientAuthorization? existing =
        await account.authorizationClient.authorizationForScopes(_scopes);
    if (existing != null) return;

    try {
      await account.authorizationClient.authorizeScopes(_scopes);
    } on GoogleSignInException catch (error) {
      throw BackupException(_describeSignInError(error));
    }
  }

  Future<Map<String, String>> _authorizationHeaders() async {
    final GoogleSignInAccount? account = _account;
    if (account == null) {
      throw BackupException('You are not signed in to a Google account.');
    }

    final Map<String, String>? headers =
        await account.authorizationClient.authorizationHeaders(_scopes);

    if (headers == null) {
      throw BackupException(
        'Google Drive access has not been granted. Press export again and '
        'approve the permission request.',
      );
    }
    return headers;
  }

  Future<String> _findOrCreateFolder(
    Map<String, String> headers,
    String name,
  ) async {
    final String? existing = await _findFolderId(headers, name);
    if (existing != null) return existing;

    final http.Response response = await _send(
      http.post(
        Uri.parse('$_driveApi/files?fields=id,name'),
        headers: <String, String>{
          ...headers,
          'Content-Type': 'application/json; charset=UTF-8',
        },
        body: jsonEncode(<String, dynamic>{
          'name': name,
          'mimeType': _folderMime,
          'parents': <String>['root'],
        }),
      ),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw BackupException(
        'Failed to create the "$name" folder in Google Drive '
        '(HTTP ${response.statusCode}).\n'
        '${_extractErrorMessage(response.body)}',
      );
    }

    return (jsonDecode(response.body) as Map<String, dynamic>)['id'] as String;
  }

  Future<String?> _findFolderId(
    Map<String, String> headers,
    String name,
  ) async {
    final String query = "name = '${_escapeQueryValue(name)}' "
        "and mimeType = '$_folderMime' and trashed = false";

    final List<Map<String, dynamic>> matches = await _listFiles(headers, query);
    if (matches.isEmpty) return null;
    return matches.first['id'] as String;
  }

  Future<String?> _findFileId(
    Map<String, String> headers,
    String folderId,
    String fileName,
  ) async {
    final String query = "name = '${_escapeQueryValue(fileName)}' "
        "and '${_escapeQueryValue(folderId)}' in parents and trashed = false";

    final List<Map<String, dynamic>> matches = await _listFiles(headers, query);
    if (matches.isEmpty) return null;
    return matches.first['id'] as String;
  }

  /// Every file matching [query], following Drive's paging.
  ///
  /// Drive answers with a page and a token, not with everything, so a folder the
  /// user has been exporting to for years would otherwise come back quietly cut
  /// off — a restore that silently skips the oldest months is worse than one
  /// that says it could not read them.
  Future<List<Map<String, dynamic>>> _listFiles(
    Map<String, String> headers,
    String query, {
    int pageSize = 10,
    String fields = 'files(id,name)',
    String? orderBy,
  }) async {
    final List<Map<String, dynamic>> collected = <Map<String, dynamic>>[];
    String? pageToken;

    for (int page = 0; page < _maxListPages; page++) {
      final Uri uri = Uri.parse('$_driveApi/files').replace(
        queryParameters: <String, String>{
          'q': query,
          'spaces': 'drive',
          'pageSize': '$pageSize',
          'fields': fields,
          if (orderBy != null) 'orderBy': orderBy,
          if (pageToken != null) 'pageToken': pageToken,
        },
      );

      final http.Response response =
          await _send(http.get(uri, headers: headers));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw BackupException(
          'Failed to read your Google Drive (HTTP ${response.statusCode}).\n'
          '${_extractErrorMessage(response.body)}',
        );
      }

      final Map<String, dynamic> body =
          jsonDecode(response.body) as Map<String, dynamic>;
      final List<dynamic> files =
          body['files'] as List<dynamic>? ?? <dynamic>[];
      collected.addAll(files.cast<Map<String, dynamic>>());

      pageToken = body['nextPageToken'] as String?;
      if (pageToken == null) break;
    }

    return collected;
  }

  /// Applies [_requestTimeout] and turns a timeout into a readable error.
  Future<http.Response> _send(Future<http.Response> request) async {
    try {
      return await request.timeout(_requestTimeout);
    } on TimeoutException {
      throw BackupException(
        'The connection to Google Drive timed out. Check your connection and try again.',
      );
    }
  }

  /// Creates a file with metadata and content in one `multipart/related` call.
  Future<http.Response> _createFile(
    Map<String, String> headers,
    String folderId,
    String fileName,
    Uint8List bytes,
  ) {
    // Unique per request so the delimiter can never collide with the payload.
    final String boundary =
        'expense-tracker-${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}';

    final String metadata = jsonEncode(<String, dynamic>{
      'name': fileName,
      'mimeType': _jsonMime,
      'parents': <String>[folderId],
    });

    final BytesBuilder body = BytesBuilder(copy: false)
      ..add(utf8.encode('--$boundary\r\n'))
      ..add(
        utf8.encode('Content-Type: application/json; charset=UTF-8\r\n\r\n'),
      )
      ..add(utf8.encode(metadata))
      ..add(utf8.encode('\r\n--$boundary\r\n'))
      ..add(utf8.encode('Content-Type: $_jsonMime; charset=UTF-8\r\n\r\n'))
      ..add(bytes)
      ..add(utf8.encode('\r\n--$boundary--'));

    return _send(
      http.post(
        Uri.parse(
          '$_uploadApi/files?uploadType=multipart&fields=id,name,webViewLink',
        ),
        headers: <String, String>{
          ...headers,
          'Content-Type': 'multipart/related; boundary=$boundary',
        },
        body: body.takeBytes(),
      ),
    );
  }

  /// Replaces the content of an existing file, keeping its id and sharing.
  Future<http.Response> _replaceFileContent(
    Map<String, String> headers,
    String fileId,
    Uint8List bytes,
  ) {
    return _send(
      http.patch(
        Uri.parse(
          '$_uploadApi/files/${Uri.encodeComponent(fileId)}'
          '?uploadType=media&fields=id,name,webViewLink',
        ),
        headers: <String, String>{
          ...headers,
          'Content-Type': '$_jsonMime; charset=UTF-8',
        },
        body: bytes,
      ),
    );
  }

  /// Escapes a value for use inside a single-quoted Drive query literal.
  String _escapeQueryValue(String value) =>
      value.replaceAll('\\', r'\\').replaceAll("'", r"\'");

  String _extractErrorMessage(String body) {
    try {
      final Object? decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final Object? error = decoded['error'];
        if (error is Map<String, dynamic>) {
          final Object? message = error['message'];
          if (message is String && message.isNotEmpty) return message;
        }
      }
    } on Object {
      // Not JSON — fall through and return the raw body instead.
    }
    return body.isEmpty ? 'The server sent no details.' : body;
  }

  String _describeSignInError(GoogleSignInException error) {
    return switch (error.code) {
      GoogleSignInExceptionCode.canceled => 'Sign-in was cancelled.',
      GoogleSignInExceptionCode.clientConfigurationError =>
        'Google Sign-In is misconfigured. Check that the package name '
            '(${GoogleConfig.androidPackageName}) and the certificate SHA-1 are '
            'registered in the Google Cloud Console, and that serverClientId '
            'holds a "Web application" client ID.',
      _ => 'Google Sign-In failed (${error.code}): ${error.description}',
    };
  }
}
