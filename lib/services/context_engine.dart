import 'dart:io';

import 'package:path/path.dart' as path;

import 'code_intelligence_service.dart';
import 'secret_scanner.dart';

class ContextFileSelection {
  const ContextFileSelection({
    required this.path,
    required this.score,
    required this.reason,
    required this.content,
  });

  final String path;
  final double score;
  final String reason;
  final String content;
}

class ContextSelection {
  const ContextSelection({required this.files, required this.promptContext});

  final List<ContextFileSelection> files;
  final String promptContext;

  int get totalCharacters => promptContext.length;
}

class ContextEngine {
  ContextEngine(String root, {CodeIntelligenceService? intelligence})
    : root = path.normalize(path.absolute(root)),
      _intelligence = intelligence ?? CodeIntelligenceService(root);

  final String root;
  final CodeIntelligenceService _intelligence;

  Future<ContextSelection> select(
    String task, {
    int maxCharacters = 12000,
    int maxFiles = 8,
  }) async {
    if (task.trim().isEmpty || maxCharacters <= 0 || maxFiles <= 0) {
      return const ContextSelection(files: [], promptContext: '');
    }
    final results = await _intelligence.search(task, limit: 200);
    final bestByPath = <String, CodeSearchResult>{};
    for (final result in results) {
      final current = bestByPath[result.path];
      if (current == null || result.score > current.score) {
        bestByPath[result.path] = result;
      }
    }
    final ranked = bestByPath.values.toList()
      ..sort((left, right) => right.score.compareTo(left.score));
    final selected = <ContextFileSelection>[];
    final buffer = StringBuffer();
    for (final candidate in ranked) {
      if (selected.length >= maxFiles) break;
      final safe = await _resolveContained(candidate.path);
      if (safe == null) continue;
      final name = path.basename(safe).toLowerCase();
      if (name == '.env' || name.startsWith('.env.')) continue;
      final file = File(safe);
      if (!await file.exists() || await file.length() > 1024 * 1024) continue;
      String content;
      try {
        content = SecretScanner.redact(await file.readAsString());
      } on FileSystemException {
        continue;
      } on FormatException {
        continue;
      }
      final reason = candidate.symbol != null
          ? 'Mendefinisikan simbol ${candidate.symbol!.name} yang cocok dengan tugas.'
          : 'Memiliki kecocokan istilah pada baris ${candidate.line}.';
      final header = '\n--- ${candidate.path} ---\nAlasan: $reason\n';
      final remaining = maxCharacters - buffer.length - header.length;
      if (remaining <= 0) break;
      if (content.length > remaining) {
        content = content.substring(0, remaining);
      }
      buffer
        ..write(header)
        ..write(content);
      selected.add(
        ContextFileSelection(
          path: candidate.path,
          score: candidate.score,
          reason: reason,
          content: content,
        ),
      );
      if (buffer.length >= maxCharacters) break;
    }
    return ContextSelection(
      files: List.unmodifiable(selected),
      promptContext: buffer.toString().trimLeft(),
    );
  }

  Future<String?> _resolveContained(String relativePath) async {
    final normalized = relativePath.replaceAll('\\', '/');
    if (normalized.isEmpty ||
        path.isAbsolute(normalized) ||
        normalized == '..' ||
        normalized.startsWith('../') ||
        normalized.contains('/../')) {
      return null;
    }
    final target = path.normalize(path.absolute(path.join(root, normalized)));
    if (!path.isWithin(root, target)) return null;
    try {
      final canonicalRoot = path.normalize(
        path.absolute(await Directory(root).resolveSymbolicLinks()),
      );
      final canonicalTarget = path.normalize(
        path.absolute(await File(target).resolveSymbolicLinks()),
      );
      return path.isWithin(canonicalRoot, canonicalTarget)
          ? canonicalTarget
          : null;
    } on FileSystemException {
      return null;
    }
  }
}
