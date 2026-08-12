import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kode_agent_desktop/services/git_service.dart';
import 'package:kode_agent_desktop/services/review_service.dart';

void main() {
  test('hasil review diformat sebagai respons chat bernomor', () {
    final result = ReviewResult(
      summary: 'Ditemukan satu bug.',
      findings: const [
        ReviewFinding(
          severity: ReviewSeverity.medium,
          category: 'bug',
          title: 'Halaman terkunci',
          path: 'script.js',
          line: 50,
          description: 'Listener dipasang terlalu lambat.',
          suggestedPatch: 'patch',
        ),
      ],
    );

    final message = formatReviewForChat(result, applicableFindings: {0});

    expect(message, contains('Git Diff Review'));
    expect(message, contains('Ditemukan satu bug.'));
    expect(message, contains('1. MEDIUM — Halaman terkunci'));
    expect(message, contains('script.js:50'));
    expect(message, contains('Listener dipasang terlalu lambat.'));
    expect(message, contains('/review-apply 1'));
    expect(message, isNot(contains('patch')));
  });

  test('review max memakai satu attempt dan deadline khusus', () {
    expect(reviewProviderMaxAttempts, 1);
    expect(
      reviewProviderTimeoutMs(
        configuredTimeoutMs: 120000,
        model: 'cx/gpt-5.6-sol(max)',
      ),
      600000,
    );
  });

  test('review non-max tidak memperpendek timeout pengguna', () {
    expect(
      reviewProviderTimeoutMs(
        configuredTimeoutMs: 420000,
        model: 'cx/gpt-5.6-sol(high)',
      ),
      420000,
    );
  });
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

  test(
    'review menolak diff file sensitif sebelum memanggil provider',
    () async {
      var analyzerCalled = false;
      final service = ReviewService(
        analyzer: (_) async {
          analyzerCalled = true;
          return '{"summary":"","findings":[]}';
        },
      );
      const diff = '''diff --git a/.env.production b/.env.production
--- a/.env.production
+++ b/.env.production
@@ -1 +1 @@
-old
+new
''';

      await expectLater(service.review(diff), throwsA(isA<FormatException>()));
      expect(analyzerCalled, isFalse);
    },
  );

  test('review menolak penghapusan file sensitif sebelum provider', () async {
    var analyzerCalled = false;
    final service = ReviewService(
      analyzer: (_) async {
        analyzerCalled = true;
        return '{"summary":"","findings":[]}';
      },
    );
    const diff = '''diff --git a/.env.production b/.env.production
--- a/.env.production
+++ /dev/null
@@ -1 +0,0 @@
-DATABASE_URL=postgresql://user:unknown-value@db/app
''';

    await expectLater(service.review(diff), throwsA(isA<FormatException>()));
    expect(analyzerCalled, isFalse);
  });

  test('patch path menolak lone CR sebagai line delimiter', () {
    const patch =
        'diff --git a/lib/client.dart b/lib/client.dart\r'
        '--- a/lib/client.dart\r'
        '+++ b/lib/client.dart\r'
        '@@ -1 +1 @@\r'
        '-before\r'
        '+after\r';

    expect(() => ReviewService.patchPaths(patch), throwsFormatException);
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

  test('review membatasi respons provider dan jumlah findings', () async {
    final oversized = ReviewService(analyzer: (_) async => 'x' * 300000);
    await expectLater(
      oversized.review('diff'),
      throwsA(isA<FormatException>()),
    );

    final tooMany = ReviewService(
      analyzer: (_) async => jsonEncode({
        'summary': 'many',
        'findings': [
          for (var index = 0; index < 51; index++)
            {
              'severity': 'low',
              'category': 'quality',
              'title': 'Finding $index',
              'path': 'lib/file.dart',
              'line': 1,
              'description': 'description',
            },
        ],
      }),
    );
    await expectLater(tooMany.review('diff'), throwsA(isA<FormatException>()));
  });

  test('patch paths mengekstrak target finding tervalidasi', () {
    const patch = '''diff --git a/lib/client.dart b/lib/client.dart
--- a/lib/client.dart
+++ b/lib/client.dart
@@ -1 +1 @@
-before
+after
''';
    expect(ReviewService.patchPaths(patch), ['lib/client.dart']);
  });

  test('patch path mendukung delimiter b slash tanpa salah target', () async {
    const target = 'lib/a b/x.dart';
    final service = ReviewService(
      analyzer: (_) async => jsonEncode({
        'summary': 'ok',
        'findings': [
          {
            'severity': 'medium',
            'category': 'bug',
            'title': 'fix',
            'path': target,
            'line': 1,
            'description': 'fix',
            'suggestedPatch': '''diff --git a/lib/a b/x.dart b/lib/a b/x.dart
--- a/lib/a b/x.dart
+++ b/lib/a b/x.dart
@@ -1 +1 @@
-old
+new
''',
          },
        ],
      }),
    );

    final result = await service.review('diff --git a/x b/x');
    expect(result.findings.single.path, target);
    expect(ReviewService.patchPaths(result.findings.single.suggestedPatch), [
      target,
    ]);
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
