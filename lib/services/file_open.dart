import 'dart:io';
import 'dart:typed_data';

import 'package:open_filex/open_filex.dart';

/// Saves a downloaded file in the app's cache folder and opens it with whatever app handles it
/// (Excel, Word...). Returns an error message, or null when it opened.
Future<String?> saveAndOpen(String name, Uint8List bytes) async {
  try {
    final safe = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '-');
    final path = '${Directory.systemTemp.path}/$safe';
    await File(path).writeAsBytes(bytes, flush: true);
    final result = await OpenFilex.open(path);
    if (result.type != ResultType.done) {
      return 'Saved as $safe, but no app was found to open it. (${result.message})';
    }
    return null;
  } catch (e) {
    return 'Could not open the file: $e';
  }
}
