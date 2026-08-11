import 'dart:convert';

import 'package:path/path.dart' as path;

import 'secret_scanner.dart';

enum ReviewSeverity { critical, high, medium, low, info }

class ReviewFinding {
  const ReviewFinding({
    required this.severity,
    required this.category,
    required this.title,
    required this.path,
    required this.line,
    required this.description,
    this.suggestedPatch = '',
  });

  final ReviewSeverity severity;
  final String category;
  final String title;
  final String path;
  final int line;
  final String description;
  final String suggestedPatch;
}

class ReviewResult {
  const ReviewResult({required this.summary, required this.findings});

  final String summary;
  final List<ReviewFinding> findings;
}

typedef ReviewAnalyzer = Future<String> Function(String prompt);

class ReviewService {
  ReviewService({required ReviewAnalyzer analyzer}) : _analyzer = analyzer;

  final ReviewAnalyzer _analyzer;

  Future<ReviewResult> review(String diff) async {
    if (diff.trim().isEmpty) {
      throw const FormatException('Tidak ada Git diff untuk direview.');
    }
    final redacted = SecretScanner.redact(
      diff,
    ).replaceAll(RegExp(r'\[REDACTED [^\]]+\]'), '[REDACTED]');
    final response = await _analyzer(
      '''Review Git diff berikut. Fokus pada bug nyata, keamanan, regresi perilaku, dan test yang hilang. Jangan laporkan masalah gaya semata.

Kembalikan hanya JSON dengan bentuk:
{"summary":"...","findings":[{"severity":"critical|high|medium|low|info","category":"bug|security|regression|quality|test","title":"...","path":"relative/path","line":1,"description":"...","suggestedPatch":"optional unified diff"}]}

GIT DIFF (secret sudah disamarkan):
$redacted''',
    );
    return _parse(response);
  }

  ReviewResult _parse(String response) {
    final normalized = response.trim();
    final fenced = RegExp(
      r'^```(?:json)?\s*([\s\S]*?)\s*```$',
      caseSensitive: false,
    ).firstMatch(normalized);
    final decoded = jsonDecode(fenced?.group(1) ?? normalized);
    if (decoded is! Map) {
      throw const FormatException('Respons review bukan objek JSON.');
    }
    final payload = Map<String, dynamic>.from(decoded);
    final summary = (payload['summary'] as String? ?? '').trim();
    final rawFindings = payload['findings'];
    if (rawFindings is! List) {
      throw const FormatException('Daftar findings review tidak valid.');
    }
    final findings = rawFindings
        .map((item) {
          if (item is! Map) {
            throw const FormatException('Finding review tidak valid.');
          }
          final finding = Map<String, dynamic>.from(item);
          final rawPath = (finding['path'] as String? ?? '').replaceAll(
            '\\',
            '/',
          );
          if (rawPath.isEmpty ||
              path.isAbsolute(rawPath) ||
              rawPath == '..' ||
              rawPath.startsWith('../') ||
              rawPath.contains('/../')) {
            throw const FormatException(
              'Path finding harus relatif ke workspace.',
            );
          }
          final severityName = (finding['severity'] as String? ?? '')
              .toLowerCase();
          final severity = ReviewSeverity.values
              .where((value) => value.name == severityName)
              .firstOrNull;
          if (severity == null) {
            throw FormatException('Severity review tidak valid: $severityName');
          }
          final line = finding['line'];
          if (line is! int || line < 1) {
            throw const FormatException('Nomor baris finding tidak valid.');
          }
          final suggestedPatch = (finding['suggestedPatch'] as String? ?? '')
              .trim();
          _validateSuggestedPatch(rawPath, suggestedPatch);
          return ReviewFinding(
            severity: severity,
            category: (finding['category'] as String? ?? 'quality').trim(),
            title: (finding['title'] as String? ?? '').trim(),
            path: rawPath,
            line: line,
            description: (finding['description'] as String? ?? '').trim(),
            suggestedPatch: suggestedPatch,
          );
        })
        .toList(growable: false);
    return ReviewResult(summary: summary, findings: findings);
  }

  void _validateSuggestedPatch(String findingPath, String patchText) {
    if (patchText.isEmpty) return;
    final basename = path.basename(findingPath).toLowerCase();
    if (basename == '.env' || basename.startsWith('.env.')) {
      throw const FormatException(
        'Suggested patch tidak boleh mengubah file environment.',
      );
    }
    final targets = RegExp(
      r'^diff --git a/(.+?) b/(.+?)$',
      multiLine: true,
    ).allMatches(patchText).toList();
    if (targets.isEmpty) {
      throw const FormatException(
        'Suggested patch harus berupa Git unified diff.',
      );
    }
    for (final target in targets) {
      final oldPath = target.group(1)!.replaceAll('\\', '/');
      final newPath = target.group(2)!.replaceAll('\\', '/');
      if (oldPath != findingPath || newPath != findingPath) {
        throw const FormatException(
          'Suggested patch hanya boleh mengubah file pada finding.',
        );
      }
    }
    final fileHeaders = RegExp(
      r'^(---|\+\+\+) (?:[ab]/)?(.+)$',
      multiLine: true,
    ).allMatches(patchText);
    for (final header in fileHeaders) {
      final headerPath = header.group(2)!.trim().replaceAll('\\', '/');
      if (headerPath == '/dev/null') continue;
      if (headerPath != findingPath) {
        throw const FormatException(
          'Suggested patch hanya boleh mengubah file pada finding.',
        );
      }
    }
  }
}
