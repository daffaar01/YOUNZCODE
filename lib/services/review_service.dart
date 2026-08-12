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

const reviewProviderMaxAttempts = 1;

int reviewProviderTimeoutMs({
  required int configuredTimeoutMs,
  required String model,
}) {
  final configured = configuredTimeoutMs > 0 ? configuredTimeoutMs : 120000;
  final normalizedModel = model.trim().toLowerCase();
  if (!normalizedModel.endsWith('(max)')) return configured;
  return configured < 600000 ? 600000 : configured;
}

String formatReviewForChat(
  ReviewResult result, {
  required Set<int> applicableFindings,
}) {
  final output = StringBuffer('Git Diff Review\n\n${result.summary.trim()}');
  if (result.findings.isEmpty) {
    output.write('\n\nTidak ditemukan masalah yang dapat ditindaklanjuti.');
    return output.toString();
  }
  for (var index = 0; index < result.findings.length; index++) {
    final finding = result.findings[index];
    output
      ..write('\n\n${index + 1}. ${finding.severity.name.toUpperCase()} — ')
      ..write(finding.title)
      ..write('\n${finding.path}:${finding.line} · ')
      ..write(finding.category.toUpperCase())
      ..write('\n${finding.description}');
    if (finding.suggestedPatch.isNotEmpty) {
      output.write(
        applicableFindings.contains(index)
            ? '\nPerbaikan tersedia dan belum diterapkan. Gunakan /review-apply ${index + 1} untuk meninjaunya melalui alur persetujuan.'
            : '\nPerbaikan yang disarankan tidak dapat diterapkan karena invalid atau stale.',
      );
    }
  }
  return output.toString();
}

class ReviewService {
  ReviewService({required ReviewAnalyzer analyzer}) : _analyzer = analyzer;

  final ReviewAnalyzer _analyzer;

  Future<ReviewResult> review(String diff) async {
    if (diff.trim().isEmpty) {
      throw const FormatException('Tidak ada Git diff untuk direview.');
    }
    if (_containsSensitiveDiffPath(diff)) {
      throw const FormatException(
        'Review provider tidak boleh menerima diff file credential sensitif.',
      );
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
    if (normalized.length > 256 * 1024) {
      throw const FormatException('Respons review terlalu besar.');
    }
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
    if (rawFindings.length > 50) {
      throw const FormatException('Jumlah findings review melebihi batas.');
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
    final targets = _patchTargets(patchText);
    if (targets.isEmpty || targets.any((target) => target != findingPath)) {
      throw const FormatException(
        'Suggested patch hanya boleh mengubah file pada finding.',
      );
    }
  }

  static List<String> patchPaths(String patchText) => _patchTargets(patchText);

  static List<String> _patchTargets(String patchText) {
    if (patchText.contains('\r')) {
      throw const FormatException(
        'Carriage return tidak didukung dalam Git unified diff.',
      );
    }
    final starts = RegExp(
      r'^diff --git ',
      multiLine: true,
    ).allMatches(patchText).map((match) => match.start).toList();
    if (starts.isEmpty) {
      throw const FormatException(
        'Suggested patch harus berupa Git unified diff.',
      );
    }
    final targets = <String>[];
    for (var index = 0; index < starts.length; index++) {
      final section = patchText.substring(
        starts[index],
        index + 1 < starts.length ? starts[index + 1] : patchText.length,
      );
      final oldHeaders = RegExp(
        r'^--- (.+)$',
        multiLine: true,
      ).allMatches(section).toList();
      final newHeaders = RegExp(
        r'^\+\+\+ (.+)$',
        multiLine: true,
      ).allMatches(section).toList();
      if (oldHeaders.length != 1 || newHeaders.length != 1) {
        throw const FormatException('Header file patch tidak valid.');
      }
      final oldPath = _safePatchHeaderPath(oldHeaders.single.group(1)!);
      final newPath = _safePatchHeaderPath(newHeaders.single.group(1)!);
      if (newPath == '/dev/null' ||
          (oldPath != '/dev/null' && oldPath != newPath)) {
        throw const FormatException('Target patch tidak valid.');
      }
      targets.add(newPath);
    }
    return targets.toSet().toList(growable: false);
  }

  static bool _containsSensitiveDiffPath(String diff) {
    if (diff.contains('\r')) {
      throw const FormatException(
        'Carriage return tidak didukung dalam Git unified diff.',
      );
    }
    const sensitiveNames = {
      '.npmrc',
      '.pypirc',
      '.netrc',
      'credentials',
      'credentials.json',
      'service-account.json',
      'id_rsa',
      'id_ed25519',
    };
    for (final match in RegExp(
      r'^(?:---|\+\+\+) (.+)$',
      multiLine: true,
    ).allMatches(diff)) {
      final safePath = _safePatchHeaderPath(match.group(1)!);
      if (safePath == '/dev/null') continue;
      final name = path.basename(safePath).toLowerCase();
      if (name == '.env' ||
          name.startsWith('.env.') ||
          sensitiveNames.contains(name)) {
        return true;
      }
    }
    return false;
  }

  static String _safePatchHeaderPath(String raw) {
    final value = raw.trim();
    if (value.startsWith('"') || value.contains(RegExp(r'[\x00-\x1F\x7F]'))) {
      throw const FormatException(
        'Quoted/control-character path tidak didukung.',
      );
    }
    final normalized = value.replaceAll('\\', '/');
    if (normalized == '/dev/null') return normalized;
    if (!(normalized.startsWith('a/') || normalized.startsWith('b/'))) {
      throw const FormatException('Header path patch tidak valid.');
    }
    final relative = normalized.substring(2);
    if (relative.isEmpty ||
        path.isAbsolute(relative) ||
        relative == '..' ||
        relative.startsWith('../') ||
        relative.contains('/../')) {
      throw const FormatException('Header path patch harus relatif.');
    }
    return relative;
  }
}
