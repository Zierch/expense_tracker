import 'package:flutter/services.dart';

import 'google_drive_service.dart' show BackupException;

/// Picks a file through Android's own file chooser and returns its text.
///
/// The platform side returns the file's *contents*, never a path: the app has no
/// business holding a path into somebody's storage, and the content URI Android
/// hands out is readable only for as long as the chooser's grant lasts.
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
}
