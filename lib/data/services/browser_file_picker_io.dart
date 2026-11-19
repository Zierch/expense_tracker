// Picking a JSON file in the browser, behind a conditional import.
//
// Android uses MainActivity's `app.files` channel instead; neither side is
// visible to the pages, which only ask for "read a text file".

import 'dart:typed_data';

/// The picked file's name and bytes, or null when the user cancels.
Future<({String name, Uint8List bytes})?> pickTextFile() async {
  throw StateError('File picking is only available on the web.');
}
