// The update flow, as state.
//
// One controller owns checking, downloading and handing off to the installer,
// because the states are one short fixed sequence — a single `sealed` type
// means every UI that switches on it is exhaustive, and a future state cannot
// silently fall out of a switch. The controller is app-scoped (`keepAlive`), so
// the banner on the dashboard and the card on the Backup page can never
// disagree about where the flow is.
//
// Talking to Android goes through the `app.updates` MethodChannel implemented
// in `MainActivity.kt`: the running version (so this file can compare it
// against the newest release) and the install hand-off for a downloaded APK.
// Both are the only pieces of Android this feature touches.

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'package:expense_tracker/data/services/app_update_service.dart';

/// The MethodChannel implemented by `MainActivity.kt`.
const MethodChannel _platform = MethodChannel('app.updates');

/// The network layer, owned by the provider so its socket can be closed when
/// the app tears the scope down.
final appUpdateServiceProvider = Provider<AppUpdateService>((ref) {
  final http.Client client = http.Client();
  ref.onDispose(client.close);
  return AppUpdateService(client: client);
});

/// The version the phone is running, straight from Android.
final appVersionProvider = FutureProvider.autoDispose<String>((ref) async {
  final Map<Object?, Object?>? info =
      await _platform.invokeMapMethod<Object?, Object?>('versionInfo');
  return info?['versionName'] as String? ?? 'unknown';
});

/// Where the update flow currently stands.
sealed class AppUpdateState {
  const AppUpdateState();
}

/// Nothing asked yet.
class UpdateIdle extends AppUpdateState {
  const UpdateIdle();
}

/// A check is on its way.
class UpdateChecking extends AppUpdateState {
  const UpdateChecking();
}

/// The newest release is not newer than what runs now.
class UpdateUpToDate extends AppUpdateState {
  const UpdateUpToDate(this.localVersion, this.latestVersion);

  final String localVersion;
  final String latestVersion;
}

/// A newer release exists, waiting to be downloaded.
class UpdateAvailable extends AppUpdateState {
  const UpdateAvailable(this.release);

  final RemoteRelease release;
}

/// Bytes are landing; [UpdateDownloading.progress] is 0.0–1.0.
class UpdateDownloading extends AppUpdateState {
  const UpdateDownloading(this.release, this.progress);

  final RemoteRelease release;
  final double progress;
}

/// The APK is fully downloaded and checksum-verified.
class UpdateReady extends AppUpdateState {
  const UpdateReady(this.release, this.filePath);

  final RemoteRelease release;
  final String filePath;
}

/// The last step failed, in words for the user; every action may be retried.
class UpdateFailed extends AppUpdateState {
  const UpdateFailed(this.message);

  final String message;
}

/// Drives the sequence: check → available → download → ready → install.
final appUpdateControllerProvider =
    NotifierProvider<AppUpdateController, AppUpdateState>(
        AppUpdateController.new);

class AppUpdateController extends Notifier<AppUpdateState> {
  AppUpdateService get _service => ref.read(appUpdateServiceProvider);

  bool _launchCheckDone = false;
  bool _downloading = false;

  @override
  AppUpdateState build() => const UpdateIdle();

  /// The one automatic check per app launch. A manual check afterwards is
  /// always allowed; repeating the launch check would spend the same GitHub
  /// rate limit twice for nothing.
  Future<void> checkOnLaunch() async {
    if (_launchCheckDone) return;
    _launchCheckDone = true;
    await _check();
  }

  /// The Backup page's button; always allowed, always fresh.
  Future<void> checkNow() => _check();

  Future<void> _check() async {
    state = const UpdateChecking();
    try {
      final Map<Object?, Object?>? info =
          await _platform.invokeMapMethod<Object?, Object?>('versionInfo');
      final String localVersion =
          info?['versionName'] as String? ?? 'unknown';

      final RemoteRelease release = await _service.fetchLatestRelease();

      if (AppUpdateService.isNewerThan(localVersion, release.version)) {
        state = UpdateAvailable(release);
      } else {
        state = UpdateUpToDate(localVersion, release.version);
      }
    } on Object catch (error) {
      state = UpdateFailed(
        error is UpdateException ? error.message : 'Update check failed: $error',
      );
    }
  }

  Future<void> download() async {
    final AppUpdateState current = state;
    if (current is! UpdateAvailable) return;
    // One download at a time: the button is disabled in the UI while bytes are
    // landing, but a re-entry here (double-tap finishing in the same frame)
    // would interleave two writes to the same file.
    if (_downloading) return;
    final RemoteRelease release = current.release;

    _downloading = true;
    state = UpdateDownloading(release, 0.0);
    try {
      final String filePath = await _service.downloadApk(
        release,
        onProgress: (double fraction) {
          if (state is UpdateDownloading) {
            state = UpdateDownloading(release, fraction);
          }
        },
      );
      state = UpdateReady(release, filePath);
    } on Object catch (error) {
      state = UpdateFailed(
        error is UpdateException ? error.message : 'Download failed: $error',
      );
    } finally {
      _downloading = false;
    }
  }

  /// Hands the verified APK to Android's package installer. The result is not
  /// awaited: the installer runs in its own process, and the user can cancel
  /// there without this app knowing or caring.
  Future<void> install() async {
    final AppUpdateState current = state;
    if (current is! UpdateReady) return;
    try {
      await _platform.invokeMethod<void>('installApk', current.filePath);
    } on Object catch (error) {
      state = UpdateFailed('Could not open the installer: $error');
    }
  }
}
