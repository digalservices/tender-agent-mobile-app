import 'package:flutter_test/flutter_test.dart';

import 'dart:typed_data';

import 'package:tender_agent_mobile/services/document_service.dart';
import 'package:tender_agent_mobile/widgets/asset_cards.dart';

void main() {
  test('formatSize', () {
    expect(formatSize(500), '500 B');
    expect(formatSize(2048), '2 KB');
    expect(formatSize(5 * 1024 * 1024), '5.0 MB');
  });

  test('limits match the web app', () {
    expect(maxFileBytes, 10 * 1024 * 1024);
    expect(supportedExtensions, ['pdf', 'docx', 'txt', 'md']);
  });

  test('looksLikeDocx accepts a zip with word/document.xml and rejects other files', () {
    final ok = Uint8List.fromList([
      0x50,
      0x4B,
      3,
      4,
      ...'word/document.xml'.codeUnits,
    ]);
    expect(looksLikeDocx(ok), true);
    expect(looksLikeDocx(Uint8List.fromList([0x50, 0x4B, 3, 4, 1, 2])), false);
    expect(looksLikeDocx(Uint8List.fromList('%PDF-1.4'.codeUnits)), false);
  });
}
