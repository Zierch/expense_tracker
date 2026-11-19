// Called only by the web build. This stub keeps `dart:html` out of the Android
// and host-test graphs; if it is ever reached, the caller is wired incorrectly.

import 'dart:typed_data';

void downloadBytes(String fileName, Uint8List bytes, {String mime = 'application/octet-stream'}) {
  throw StateError('Browser downloads are only available on the web.');
}
