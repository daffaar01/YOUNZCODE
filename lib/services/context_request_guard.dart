import 'dart:io';

import 'package:path/path.dart' as path;

class ContextRequestLease {
  const ContextRequestLease._({
    required this.workspace,
    required this.canonicalWorkspace,
    required this.engine,
  });

  final String workspace;
  final String canonicalWorkspace;
  final Object engine;

  static Future<ContextRequestLease> capture({
    required String workspace,
    required bool trusted,
    required Object engine,
  }) async {
    if (!trusted || workspace.isEmpty) {
      throw StateError('Workspace context is not trusted.');
    }
    return ContextRequestLease._(
      workspace: workspace,
      canonicalWorkspace: await _canonical(workspace),
      engine: engine,
    );
  }

  Future<bool> isCurrent({
    required String workspace,
    required bool trusted,
    required Object? engine,
  }) async {
    if (!trusted ||
        workspace != this.workspace ||
        !identical(engine, this.engine)) {
      return false;
    }
    try {
      return await _canonical(workspace) == canonicalWorkspace;
    } on FileSystemException {
      return false;
    }
  }

  static Future<String> _canonical(String workspace) async {
    final resolved = await Directory(workspace).resolveSymbolicLinks();
    final normalized = path.normalize(path.absolute(resolved));
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }
}

class ContextBoundPrompt {
  const ContextBoundPrompt(this.prompt, {this.lease});

  final String prompt;
  final ContextRequestLease? lease;
}
