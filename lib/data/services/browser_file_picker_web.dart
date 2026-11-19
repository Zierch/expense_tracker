import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

// ignore: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;

Future<({String name, Uint8List bytes})?> pickTextFile() {
  final html.InputElement input = html.InputElement(type: 'file')
    ..accept = '.json,application/json'
    ..style.display = 'none';
  html.document.body?.children.add(input);

  final Completer<({String name, Uint8List bytes})?> done =
      Completer<({String name, Uint8List bytes})?>();

  void cleanup() {
    input.remove();
  }

  input.onChange.first.then((html.Event _) async {
    final List<html.File>? files = input.files;
    if (files == null || files.isEmpty) {
      cleanup();
      if (!done.isCompleted) done.complete(null);
      return;
    }
    final html.File file = files.first;
    // The picker only accepts JSON, so text is the whole file. Encoding it
    // keeps one signature on both platforms.
    final html.FileReader reader = html.FileReader();
    final Completer<String> text = Completer<String>();
    reader.onLoadEnd.first.then((_) => text.complete(reader.result as String));
    reader.onError.first.then((_) => text.completeError(StateError('Could not read the file')));
    reader.readAsText(file);
    final String content = await text.future;
    cleanup();
    if (!done.isCompleted) {
      done.complete((name: file.name, bytes: utf8.encode(content)));
    }
  });

  input.click();
  return done.future;
}
