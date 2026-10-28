import 'package:flutter/services.dart';

import 'google_drive_service.dart' show BackupException;

/// Reads a backup file, and saves a report, through Android's own file dialogs.
///
/// The platform side returns the chosen file's *contents*, never a path: the app
/// has no business holding a path into somebody's storage, and the content URI
/// Android hands out is readable only for as long as the chooser's grant lasts.
class FilePickerService {
  FilePickerService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('app.files');

  final MethodChannel _channel;

  /// The chosen file's text, or `null` when the user backed out of the chooser.
  Future<String?> pickJsonText() async {
    try {
      return await _channel.invokeMethod<String>('pickJsonFile');
    } on MissingPluginException {
      // Host tests, and any platform without the channel. Told plainly rather
      // than swallowed: a silent "nothing happened" reads as a broken button.
      throw BackupException('Choosing a file is not available on this device.');
    } on PlatformException catch (error) {
      throw BackupException(error.message ?? 'Could not read the chosen file.');
    }
  }

  /// Writes [text] to a file the user names and places in Android's "Save as"
  /// dialog. `false` means they backed out, which is not a failure.
  Future<bool> saveTextFile({
    required String fileName,
    required String text,
  }) async {
    try {
      final bool? saved = await _channel.invokeMethod<bool>(
        'saveTextFile',
        <String, Object?>{'fileName': fileName, 'text': text},
      );
      return saved ?? false;
    } on MissingPluginException {
      throw BackupException('Saving a file is not available on this device.');
    } on PlatformException catch (error) {
      throw BackupException(error.message ?? 'Could not save the file.');
    }
  }
}
