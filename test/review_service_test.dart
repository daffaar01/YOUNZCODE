import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kode_agent_desktop/services/git_service.dart';
import 'package:kode_agent_desktop/services/review_service.dart';

void main() {
  test(
    'review mengirim diff teredaksi dan mengurai temuan terstruktur',
    () async {
      late String prompt;
      final service = ReviewService(
        analyzer: (value) async {
          prompt = value;
          return '''```json
${jsonEncode({
            'summary': 'Satu risiko keamanan.',
            'findings': [
              {'severity': 'high', 'category': 'security', 'title': 'Token dicatat ke log', 'path': 'lib/client.dart', 'line': 12, 'description': 'Token dapat bocor melalui log.', 'suggestedPatch': ''},
            ],
          })}
```''';
        },
      );

      final result = await service.review(
        '''diff --git a/lib/client.dart b/lib/client.dart
--- a/lib/client.dart
+++ b/lib/client.dart
@@ -10,1 +10,2 @@
+const token = "sk-abcdefghijklmnopqrstuvwxyz123456";
+print(token);
''',
      );

      expect(prompt, isNot(contains('sk-abcdefghijklmnopqrstuvwxyz123456')));
      expect(prompt, contains('[REDACTED]'));
      expect(result.summary, 'Satu risiko keamanan.');
      expect(result.findings.single.severity, ReviewSeverity.high);
      expect(result.findings.single.path, 'lib/client.dart');
      expect(result.findings.single.line, 12);
    },
  );

  test('review menolak suggested patch yang menyentuh file lain', () async {
    final service = ReviewService(
      analyzer: (_) async => jsonEncode({
        'summary': 'patch silang file',
        'findings': [
          {
            'severity': 'high',
            'category': 'security',
            'title': 'Finding client',
            'path': 'lib/client.dart',
            'line': 1,
            'description': 'Patch tidak boleh menyentuh file lain.',
            'suggestedPatch': '''diff --git a/lib/other.dart b/lib/other.dart
--- a/lib/other.dart
+++ b/lib/other.dart
@@ -1 +1 @@
-before
+after
''',
          },
        ],
      }),
    );

    await expectLater(service.review('diff'), throwsA(isA<FormatException>()));
  });

  test('review menolak section patch tambahan tanpa header Git', () async {
    final service = ReviewService(
      analyzer: (_) async => jsonEncode({
        'summary': 'patch tersembunyi',
        'findings': [
          {
            'severity': 'high',
            'category': 'security',
            'title': 'Finding client',
            'path': 'lib/client.dart',
            'line': 1,
            'description': 'Section tambahan harus ditolak.',
            'suggestedPatch': '''diff --git a/lib/client.dart b/lib/client.dart
--- a/lib/client.dart
+++ b/lib/client.dart
@@ -1 +1 @@
-before
+after
--- a/.env
+++ b/.env
@@ -1 +1 @@
-safe
+leaked
''',
          },
        ],
      }),
    );

    await expectLater(service.review('diff'), throwsA(isA<FormatException>()));
  });

  test('review menolak suggested patch untuk environment file', () async {
    final service = ReviewService(
      analyzer: (_) async => jsonEncode({
        'summary': 'environment file',
        'findings': [
          {
            'severity': 'critical',
            'category': 'security',
            'title': 'Ubah env',
            'path': '.env',
            'line': 1,
            'description': 'Environment file dilindungi.',
            'suggestedPatch': '''diff --git a/.env b/.env
--- a/.env
+++ b/.env
@@ -1 +1 @@
-before
+after
''',
          },
        ],
      }),
    );

    await expectLater(service.review('diff'), throwsA(isA<FormatException>()));
  });

  test('review menolak path absolut dari provider', () async {
    final service = ReviewService(
      analyzer: (_) async => jsonEncode({
        'summary': 'invalid',
        'findings': [
          {
            'severity': 'medium',
            'category': 'bug',
            'title': 'Invalid path',
            'path': 'C:/secret.txt',
            'line': 1,
            'description': 'Tidak boleh diterima.',
          },
        ],
      }),
    );

    await expectLater(service.review('diff'), throwsA(isA<FormatException>()));
  });

  test('GitService memeriksa patch sebelum menerapkannya', () async {
    final root = await Directory.systemTemp.createTemp('younz-review-');
    addTearDown(() => root.delete(recursive: true));
    await _git(root.path, ['init']);
    await _git(root.path, ['config', 'user.email', 'test@example.com']);
    await _git(root.path, ['config', 'user.name', 'YOUNZ Test']);
    final file = File('${root.path}${Platform.pathSeparator}sample.txt');
    await file.writeAsString('before\n');
    await _git(root.path, ['add', 'sample.txt']);
    await _git(root.path, ['commit', '-m', 'initial']);
    const patch = '''diff --git a/sample.txt b/sample.txt
--- a/sample.txt
+++ b/sample.txt
@@ -1 +1 @@
-before
+after
''';
    const service = GitService();

    await service.checkPatch(root.path, patch);
    expect(await file.readAsString(), 'before\n');
    await service.applyPatch(root.path, patch);
    expect((await file.readAsString()).replaceAll('\r\n', '\n'), 'after\n');

    await service.reversePatch(root.path, patch);
    expect((await file.readAsString()).replaceAll('\r\n', '\n'), 'before\n');

    await service.applyPatch(root.path, patch);

    await expectLater(
      service.applyPatch(root.path, patch),
      throwsA(isA<ProcessException>()),
    );
  });
}

Future<void> _git(String workspace, List<String> arguments) async {
  final result = await Process.run(
    'git',
    arguments,
    workingDirectory: workspace,
  );
  if (result.exitCode != 0) {
    throw ProcessException('git', arguments, '${result.stderr}');
  }
}
