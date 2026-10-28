package com.zierch.expense_tracker

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File

/// The Android side of in-app updates, on the `app.updates` channel:
///
/// * `versionInfo` — the running app's version name and code, so the Dart side
///   can compare it against the newest GitHub release.
/// * `installApk` — hands a downloaded APK to the platform package installer
///   through a `FileProvider` URI, because Android will not let an app open a
///   raw file path with another process, and the installer needs read access
///   that is granted per-URI rather than per-file-system.
///
/// And the Android side of importing a backup file, on the `app.files` channel:
///
/// * `pickJsonFile` — opens the system file chooser and returns the chosen
///   file's text, or `null` when the user backs out.
/// And the Android side of the reports, on the same `app.files` channel:
///
/// * `pickJsonFile` — opens the system file chooser and returns the chosen
///   file's text, or `null` when the user backs out.
/// * `saveTextFile` — opens the system "Save as" dialog and writes the given
///   text where the user chose, or returns `false` when they back out.
class MainActivity : FlutterActivity() {
    /// A chooser or a save dialog answers long after the call that opened it, so
    /// the reply waits here until the user has picked a place or backed out.
    private var pendingPick: MethodChannel.Result? = null

    /// The text a save is going to write, held from the moment the dialog opens
    /// until the user has said where it goes.
    private var pendingText: String? = null

    /// True once this activity has been destroyed. A read or a write may still be
    /// running on its worker thread and its reply is the worker's to answer by then
    /// — the slot was cleared before that thread started, so `onDestroy` has
    /// nothing to answer for. What this flag decides is *what* the worker answers:
    /// a result nobody is left to receive is reported as the interruption it is.
    private var destroyed = false

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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.files")
                .setMethodCallHandler { call, result ->
                    when (call.method) {
                        "pickJsonFile" -> pickJsonFile(result)
                        "saveTextFile" -> saveTextFile(call.arguments as Map<*, *>, result)
                        else -> result.notImplemented()
                    }
                }
    }

    /// A dialog cannot survive this activity being torn down and rebuilt: the
    /// reply belongs to the instance that opened it. Answering the caller with an
    /// error here is what keeps the screen from waiting forever on a reply that
    /// will never come.
    override fun onDestroy() {
        destroyed = true
        pendingPick?.let { reply ->
            pendingPick = null
            pendingText = null
            reply.error("dialog_cancelled", "The file dialog was interrupted.", null)
        }
        super.onDestroy()
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

    private fun pickJsonFile(result: MethodChannel.Result) {
        // One dialog at a time: a second call while one is open would overwrite
        // the first caller's reply and leave it waiting forever.
        if (pendingPick != null) {
            result.error("pick_in_progress", "A file is already being chosen.", null)
            return
        }
        pendingPick = result

        // Every type, not just `application/json`: file providers disagree about
        // what a `.json` is — Downloads says `application/json`, some file
        // managers and cloud providers say `text/plain` or
        // `application/octet-stream` — and a filter Android applies too strictly
        // shows the user a list without their own backup in it. What the file
        // actually contains is checked on the Dart side, where a wrong file is a
        // message rather than a missing row in the chooser.
        val chooser =
                Intent(Intent.ACTION_OPEN_DOCUMENT)
                        .addCategory(Intent.CATEGORY_OPENABLE)
                        .setType("*/*")
        try {
            startActivityForResult(chooser, PICK_JSON_REQUEST)
        } catch (t: Throwable) {
            // A device with nothing installed to answer a chooser throws here.
            // The slot is cleared first: leaving it set would refuse every later
            // pick as "already in progress" and the button would never work
            // again for the rest of the session.
            pendingPick = null
            result.error("pick_unavailable", t.message, null)
        }
    }

    /// Writes [arguments]' text to a file the user names and places.
    ///
    /// `ACTION_CREATE_DOCUMENT` rather than the share sheet: a report is a file
    /// the user keeps and opens later, and the storage access framework needs no
    /// permission for it to write wherever they point. Android hands back a URI
    /// this app may write to once; nothing else about the file is this app's.
    private fun saveTextFile(arguments: Map<*, *>, result: MethodChannel.Result) {
        val fileName = arguments["fileName"] as? String
        val text = arguments["text"] as? String
        if (fileName.isNullOrEmpty() || text == null) {
            result.error("invalid_arguments", "A file name and its contents are required.", null)
            return
        }
        if (pendingPick != null) {
            result.error("pick_in_progress", "Another file is already being chosen or saved.", null)
            return
        }
        pendingPick = result
        pendingText = text

        val dialog =
                Intent(Intent.ACTION_CREATE_DOCUMENT)
                        .addCategory(Intent.CATEGORY_OPENABLE)
                        .setType("text/csv")
                        .putExtra(Intent.EXTRA_TITLE, fileName)
        try {
            startActivityForResult(dialog, SAVE_TEXT_REQUEST)
        } catch (t: Throwable) {
            pendingPick = null
            pendingText = null
            result.error("save_unavailable", t.message, null)
        }
    }

    /// The chooser's or the save dialog's answer.
    ///
    /// `startActivityForResult` is the older of the two ways to ask Android for a
    /// file, and it is the one that works here: the newer
    /// `registerForActivityResult` belongs to `ComponentActivity`, which the
    /// activity this app extends is not.
    @Deprecated("startActivityForResult", ReplaceWith("registerForActivityResult"))
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != PICK_JSON_REQUEST && requestCode != SAVE_TEXT_REQUEST) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }

        val reply = pendingPick ?: return
        val text = pendingText
        pendingPick = null
        pendingText = null

        val uri = if (resultCode == Activity.RESULT_OK) data?.data else null
        if (uri == null) {
            // Backed out. Not an error: the caller reads it as "nothing was
            // chosen" (or "nothing was saved") and says nothing to the user.
            reply.success(if (requestCode == SAVE_TEXT_REQUEST) false else null)
            return
        }

        // The slot is cleared here, so `onDestroy` will not answer for this reply
        // however the activity is torn down next. That leaves this thread owing an
        // answer whatever happens, including when the activity is already gone —
        // an unrecognised reply is still an answer, and the Dart side is waiting on
        // one. A silent return would leave that `await` unfinished for the life of
        // the process.
        fun answer(outcome: Result<Any?>, failureCode: String) {
            runOnUiThread {
                if (destroyed) {
                    reply.error("dialog_cancelled", "The file dialog was interrupted.", null)
                    return@runOnUiThread
                }
                outcome
                        .onSuccess { reply.success(it) }
                        .onFailure { reply.error(failureCode, it.message, null) }
            }
        }

        // Off the main thread: a provider can be a cloud app that streams the
        // file over the network, and a blocking read of up to ten megabytes on
        // the UI thread is an ANR for anything but the fastest case. The reply is
        // posted back to the main thread, which is where Flutter's channel
        // expects to be answered.
        Thread {
            if (requestCode == SAVE_TEXT_REQUEST) {
                answer(runCatching { writeText(uri, text ?: "") }, "write_failed")
            } else {
                answer(runCatching { readJson(uri) }, "read_failed")
            }
        }.start()
    }

    /// [text] written to [uri], which the save dialog just handed out.
    private fun writeText(uri: Uri, text: String): Boolean {
        // `"wt"`, not `"w"`: the platform documents `"w"` as "may or may not
        // truncate", so saving over a longer file could leave the old tail
        // behind. This app asks for a fresh document, but a provider is free to
        // hand back one that already exists.
        val output = contentResolver.openOutputStream(uri, "wt")
                ?: throw IllegalStateException("Could not open the chosen file for writing.")

        output.use { stream ->
            stream.write(text.toByteArray(Charsets.UTF_8))
            stream.flush()
        }
        return true
    }

    /// The chosen file as text.
    private fun readJson(uri: Uri): String {
        val input = contentResolver.openInputStream(uri)
                ?: throw IllegalStateException("Could not open the chosen file.")

        input.use { stream ->
            val buffer = ByteArray(64 * 1024)
            val collected = ByteArrayOutputStream()

            // The size is counted while reading rather than taken from what the
            // provider reports, because a provider may report nothing at all.
            var total = 0
            while (true) {
                val read = stream.read(buffer)
                if (read <= 0) {
                    break
                }
                total += read
                if (total > MAX_IMPORT_BYTES) {
                    throw IllegalStateException(
                            "That file is larger than ${MAX_IMPORT_BYTES / (1024 * 1024)} MB, " +
                                    "so it is not one of this app's month backups."
                    )
                }
                collected.write(buffer, 0, read)
            }

            return collected.toString("UTF-8")
        }
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

    private companion object {
        /// Identifies this app's own file-chooser request in `onActivityResult`.
        const val PICK_JSON_REQUEST = 0x1F0

        /// Identifies the "Save as" request in `onActivityResult`.
        const val SAVE_TEXT_REQUEST = 0x1F1

        /// A month of transactions is tens of kilobytes. Anything past this is
        /// not a backup this app wrote, and reading it would only cost memory.
        const val MAX_IMPORT_BYTES = 10 * 1024 * 1024
    }
}