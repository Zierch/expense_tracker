/// Configuration for the Google sign-in / Google Drive backup integration.
///
/// Everything here is filled in from the Google Cloud Console. See the
/// "Using your own Google OAuth client" section in README.md for the guide.
class GoogleConfig {
  /// OAuth client ID of type **Web application**.
  ///
  /// Android identifies the app through the package name + signing SHA-1, but
  /// `google_sign_in` still needs a server (web) client ID to talk to Google's
  /// backend, so paste the *Web application* client ID here — not the Android
  /// one.
  static const String serverClientId =
      '942402832440-behej3ecogkms8uvcc297ggmiif580c9.apps.googleusercontent.com';

  /// Folder inside "My Drive" that archived files are written to.
  static const String driveFolderName = 'Expense Tracker';

  /// Only non-sensitive scope we need: lets the app see the files *it* created.
  ///
  /// Because this scope is not sensitive, the app does not have to go through
  /// Google's OAuth verification process.
  static const String driveFileScope =
      'https://www.googleapis.com/auth/drive.file';

  /// Kept only so error messages can point at the right registration entry.
  static const String androidPackageName = 'com.zierch.expense_tracker';

  /// Whether [serverClientId] looks like a real client ID yet.
  ///
  /// The length check catches a truncated paste — a real web client ID is
  /// around 70 characters and ends with `.apps.googleusercontent.com`.
  static bool get isConfigured =>
      serverClientId.isNotEmpty &&
      !serverClientId.startsWith('PASTE_') &&
      serverClientId.length >= 20;
}
