import 'code_intelligence_service.dart';

typedef ContextReadHook = Future<void> Function(String canonicalPath);

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
  ContextEngine(
    String root, {
    CodeIntelligenceService? intelligence,
    ContextReadHook? beforeRead,
  });

  /// Automatic workspace reads are intentionally disabled.
  ///
  /// `dart:io` does not expose a portable no-follow, handle-bound read API.
  /// Path validation before and after an asynchronous read cannot prevent a
  /// target from being swapped temporarily, so failing closed is the only
  /// portable way to guarantee automatic context cannot disclose another file.
  Future<ContextSelection> select(
    String task, {
    int maxCharacters = 12000,
    int maxFiles = 8,
    Set<String> excludedPaths = const {},
  }) async => const ContextSelection(files: [], promptContext: '');
}
