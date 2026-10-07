@Tags(['safety'])
library;

import 'dart:io';

import 'package:test/test.dart';

/// Enforces ADR-001 and ADR-006 on the source itself, so the rules don't
/// depend on reviewers noticing.
void main() {
  final sources = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  test('there are sources to check', () {
    expect(sources, isNotEmpty);
  });

  test('only FileMutator calls move/delete/dehydrate on the file system', () {
    final call = RegExp(r'(\w+)\.(move|delete|dehydrate)\(');
    final allowedFiles = {'file_mutator.dart', 'platform_fs.dart'};
    final allowedReceivers = {'_mutator', 'mutator'};
    final offenders = <String>[];
    for (final f in sources) {
      final name = f.uri.pathSegments.last;
      if (allowedFiles.contains(name)) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        for (final m in call.allMatches(lines[i])) {
          if (!allowedReceivers.contains(m.group(1))) {
            offenders.add('${f.path}:${i + 1}: ${lines[i].trim()}');
          }
        }
      }
    }
    expect(offenders, isEmpty);
  });

  test('core stays pure: no dart:io, Flutter or Win32 imports', () {
    final banned = RegExp(
        r'''^\s*import\s+['"](dart:io|package:flutter|package:win32)''');
    final offenders = [
      for (final f in sources)
        for (final line in f.readAsLinesSync())
          if (banned.hasMatch(line)) '${f.path}: $line',
    ];
    expect(offenders, isEmpty);
  });
}
