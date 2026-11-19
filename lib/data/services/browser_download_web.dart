// Browser download through a Blob and a temporary anchor.
//
// The click happens inside the button's callback rather than after a later
// async gap where possible: browsers allow a download from a user gesture.

import 'dart:typed_data';

// ignore: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;

void downloadBytes(String fileName, Uint8List bytes, {String mime = 'application/octet-stream'}) {
  final html.Blob blob = html.Blob(<dynamic>[bytes], mime);
  final String url = html.Url.createObjectUrlFromBlob(blob);
  final html.AnchorElement anchor = html.AnchorElement(href: url)
    ..setAttribute('download', fileName)
    ..style.display = 'none';
  html.document.body?.children.add(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
}
