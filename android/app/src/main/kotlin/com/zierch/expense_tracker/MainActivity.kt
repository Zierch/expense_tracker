package com.zierch.expense_tracker

import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/// The Android side of in-app updates, on the `app.updates` channel:
///
/// * `versionInfo` — the running app's version name and code, so the Dart side
///   can compare it against the newest GitHub release.
/// * `installApk` — hands a downloaded APK to the platform package installer
///   through a `FileProvider` URI, because Android will not let an app open a
///   raw file path with another process, and the installer needs read access
///   that is granted per-URI rather than per-file-system.
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.updates")
                .setMethodCallHandler { call, result ->
                    when (call.method) {
                        "versionInfo" -> versionInfo(result)
                        "installApk" -> installApk(call.arguments as String, result)
                        else -> result.notImplemented()
                    }
                }
    }

    private fun versionInfo(result: MethodChannel.Result) {
        val info = packageManager.getPackageInfo(packageName, 0)
        val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            info.versionCode.toLong()
        }
        result.success(mapOf("versionName" to info.versionName, "versionCode" to versionCode))
    }

    private fun installApk(rawPath: String, result: MethodChannel.Result) {
        try {
            // Only APKs that this app itself downloaded may reach the installer,
            // and only from the directory that holds them: the Dart side names
            // the file, this side decides what that name is allowed to mean.
            val allowed = File(cacheDir, "apk").canonicalFile
            val file = File(rawPath).canonicalFile
            if (!file.path.startsWith(allowed.path + File.separator)) {
                result.error("invalid_path", "The APK was not downloaded by this app.", null)
                return
            }
            val uri = FileProvider.getUriForFile(this, "$packageName.fileProvider", file)
            val intent =
                    Intent(Intent.ACTION_VIEW)
                            .setDataAndType(uri, "application/vnd.android.package-archive")
                            .addFlags(
                                    Intent.FLAG_ACTIVITY_NEW_TASK or
                                            Intent.FLAG_GRANT_READ_URI_PERMISSION)
            startActivity(intent)
            result.success(true)
        } catch (t: Throwable) {
            result.error("install_failed", t.message, null)
        }
    }
}
