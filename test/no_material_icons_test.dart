import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Keeps emoji and stray unicode out of the UI code (they render as colour
/// emoji or "?" boxes on some devices). Use Icon(Icons.x) for icons.
void main() {
  test('lib/ code is ASCII only (outside comments)', () {
    final bad = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final code = lines[i].split('//').first;
        if (code.runes.any((r) => r > 127)) bad.add('${f.path}:${i + 1}');
      }
    }
    expect(bad, isEmpty);
  });
}
