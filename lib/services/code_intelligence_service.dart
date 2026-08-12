import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path;

class CodeSymbol {
  const CodeSymbol({
    required this.name,
    required this.kind,
    required this.path,
    required this.line,
    required this.preview,
  });

  final String name;
  final String kind;
  final String path;
  final int line;
  final String preview;
}

class CodeSearchResult {
  const CodeSearchResult({
    required this.path,
    required this.line,
    required this.preview,
    required this.score,
    this.symbol,
  });

  final String path;
  final int line;
  final String preview;
  final double score;
  final CodeSymbol? symbol;

  String get displayLine => '$path:$line:$preview';
}

class CodeIntelligenceService {
  CodeIntelligenceService(this.root);

  final String root;
  final List<_IndexedLine> _lines = [];
  final List<CodeSymbol> _symbols = [];
  final Map<String, String> _fingerprints = {};
  Future<void>? _indexing;
  Future<void> _refreshQueue = Future.value();
  bool _invalidated = true;

  static const _extensions = {
    '.dart',
    '.py',
    '.js',
    '.jsx',
    '.mjs',
    '.cjs',
    '.ts',
    '.tsx',
    '.java',
    '.kt',
    '.kts',
    '.go',
    '.rs',
    '.c',
    '.cc',
    '.cpp',
    '.h',
    '.hpp',
    '.cs',
    '.swift',
    '.php',
    '.rb',
    '.vue',
    '.svelte',
    '.html',
    '.css',
    '.scss',
    '.json',
    '.yaml',
    '.yml',
    '.toml',
    '.md',
  };

  static const _ignoredDirectories = {
    '.git',
    '.dart_tool',
    '.idea',
    '.vscode',
    'build',
    'dist',
    'node_modules',
    'vendor',
    'coverage',
    'graphify-out',
    'release',
  };

  static const _relatedTerms = <String, Set<String>>{
    'auth': {'login', 'token', 'credential', 'security', 'session'},
    'login': {'auth', 'token', 'credential', 'session'},
    'save': {'store', 'persist', 'write', 'cache'},
    'search': {'find', 'query', 'lookup', 'filter'},
    'error': {'exception', 'failure', 'invalid'},
    'config': {'settings', 'preference', 'option'},
    'delete': {'remove', 'discard', 'clear'},
    'update': {'edit', 'change', 'replace', 'modify'},
    'permission': {'approval', 'allow', 'trust', 'security'},
    'simpan': {'save', 'store', 'persist', 'write'},
    'cari': {'search', 'find', 'query', 'lookup'},
    'ubah': {'update', 'edit', 'change', 'replace'},
    'hapus': {'delete', 'remove', 'discard', 'clear'},
    'izin': {'permission', 'approval', 'allow', 'trust'},
    'pengguna': {'user', 'account', 'profile'},
    'berkas': {'file', 'document', 'path'},
  };

  List<CodeSymbol> get symbols => List.unmodifiable(_symbols);
  Set<String> get symbolNames => {for (final symbol in _symbols) symbol.name};

  void invalidate() => _invalidated = true;

  Future<void> refreshExternalChanges() async {
    await ensureIndexed();
    final current = <String, String>{};
    if (!await Directory(root).exists()) return;
    await for (final entity in Directory(
      root,
    ).list(recursive: true, followLinks: false)) {
      if (entity is! File || !_shouldIndex(entity.path)) continue;
      final relative = _relativeKey(entity.path);
      try {
        final contained = await _resolveContainedFile(relative);
        if (contained == null || await contained.length() > 1024 * 1024) {
          continue;
        }
        final content = await contained.readAsString();
        if (content.contains('\u0000')) continue;
        final stat = await contained.stat();
        current[relative] = _fingerprint(stat, content);
      } on FileSystemException {
        continue;
      } on FormatException {
        continue;
      }
      if (current.length >= 20000) break;
    }
    final changed = <String>{
      ..._fingerprints.keys,
      ...current.keys,
    }.where((item) => _fingerprints[item] != current[item]).toSet();
    if (changed.isNotEmpty) await refreshPaths(changed);
  }

  Future<void> refreshPaths(Iterable<String> relativePaths) {
    final snapshot = relativePaths.map(_normalizeRelativeKey).toSet();
    final refresh = _refreshQueue.then((_) => _refreshPaths(snapshot));
    _refreshQueue = refresh.catchError((_) {});
    return refresh;
  }

  Future<void> _refreshPaths(Set<String> relativePaths) async {
    await ensureIndexed();
    for (final relativePath in relativePaths) {
      final normalized = _normalizeRelativeKey(relativePath);
      if (normalized.isEmpty ||
          path.isAbsolute(normalized) ||
          normalized == '..' ||
          normalized.startsWith('../') ||
          normalized.contains('/../')) {
        continue;
      }
      _lines.removeWhere((line) => line.path == normalized);
      _symbols.removeWhere((symbol) => symbol.path == normalized);
      _fingerprints.remove(normalized);
      final file = await _resolveContainedFile(normalized);
      if (file == null || !_shouldIndex(file.path)) continue;
      try {
        if (await file.length() > 1024 * 1024) continue;
        final content = await file.readAsString();
        final revalidated = await _resolveContainedFile(normalized);
        if (revalidated == null || revalidated.path != file.path) continue;
        if (!content.contains('\u0000')) {
          _indexFile(file.path, content, relativeKey: normalized);
          final stat = await file.stat();
          _fingerprints[normalized] = _fingerprint(stat, content);
        }
      } on FileSystemException {
        // A file may disappear while an editor is saving it.
      } on FormatException {
        // Ignore malformed/non-UTF8 files, matching full indexing behavior.
      }
    }
  }

  Future<void> ensureIndexed() {
    if (!_invalidated) return Future.value();
    return _indexing ??= _rebuild().whenComplete(() => _indexing = null);
  }

  Future<List<CodeSearchResult>> search(String query, {int limit = 300}) async {
    await ensureIndexed();
    final exact = _tokens(query);
    if (exact.isEmpty) return const [];
    final expanded = <String>{...exact};
    for (final token in exact) {
      expanded.addAll(_relatedTerms[token] ?? const {});
    }
    final ranked = <CodeSearchResult>[];
    for (final symbol in _symbols) {
      final haystack = '${symbol.name} ${symbol.kind} ${symbol.path}'
          .toLowerCase();
      final score = _score(haystack, exact, expanded, symbol: true);
      if (score <= 0) continue;
      ranked.add(
        CodeSearchResult(
          path: symbol.path,
          line: symbol.line,
          preview: '${symbol.kind} ${symbol.name} — ${symbol.preview.trim()}',
          score: score,
          symbol: symbol,
        ),
      );
    }
    for (final indexed in _lines) {
      final score = _score(indexed.searchable, exact, expanded);
      if (score <= 0) continue;
      ranked.add(
        CodeSearchResult(
          path: indexed.path,
          line: indexed.line,
          preview: indexed.text.trim(),
          score: score,
        ),
      );
    }
    ranked.sort((left, right) {
      final byScore = right.score.compareTo(left.score);
      if (byScore != 0) return byScore;
      final byPath = left.path.compareTo(right.path);
      return byPath != 0 ? byPath : left.line.compareTo(right.line);
    });
    final seen = <String>{};
    final perPath = <String, int>{};
    final selected = <CodeSearchResult>[];
    for (final result in ranked) {
      if (!seen.add('${result.path}:${result.line}')) continue;
      final count = perPath[result.path] ?? 0;
      if (count >= 8) continue;
      perPath[result.path] = count + 1;
      selected.add(result);
      if (selected.length >= limit) break;
    }
    return selected;
  }

  Future<List<CodeSearchResult>> references(
    String symbol, {
    int limit = 300,
  }) async {
    await ensureIndexed();
    final trimmed = symbol.trim();
    if (trimmed.isEmpty) return const [];
    final pattern = RegExp(
      '(?<![A-Za-z0-9_])${RegExp.escape(trimmed)}(?![A-Za-z0-9_])',
      caseSensitive: true,
    );
    return [
      for (final indexed in _lines)
        if (pattern.hasMatch(indexed.text))
          CodeSearchResult(
            path: indexed.path,
            line: indexed.line,
            preview: indexed.text.trim(),
            score: 1,
          ),
    ].take(limit).toList();
  }

  Future<CodeSymbol?> definition(String symbol) async {
    await ensureIndexed();
    final exact = _symbols.where((item) => item.name == symbol).toList();
    if (exact.isNotEmpty) return exact.first;
    final lower = symbol.toLowerCase();
    return _symbols.cast<CodeSymbol?>().firstWhere(
      (item) => item!.name.toLowerCase() == lower,
      orElse: () => null,
    );
  }

  Future<void> _rebuild() async {
    _lines.clear();
    _symbols.clear();
    _fingerprints.clear();
    if (root.isEmpty || !await Directory(root).exists()) {
      _invalidated = false;
      return;
    }
    final files = <File>[];
    await for (final entity in Directory(
      root,
    ).list(recursive: true, followLinks: false)) {
      if (entity is! File || !_shouldIndex(entity.path)) continue;
      files.add(entity);
      if (files.length >= 20000) break;
    }
    files.sort((left, right) => left.path.compareTo(right.path));
    for (final file in files) {
      try {
        if (await file.length() > 1024 * 1024) continue;
        final content = await file.readAsString();
        if (content.contains('\u0000')) continue;
        final relative = _relativeKey(file.path);
        _indexFile(file.path, content, relativeKey: relative);
        final stat = await file.stat();
        _fingerprints[relative] = _fingerprint(stat, content);
      } on FileSystemException {
        // Files can disappear while a workspace is being indexed.
      } on FormatException {
        // Skip non-UTF8 or otherwise malformed text.
      }
    }
    _invalidated = false;
  }

  static String _fingerprint(FileStat stat, String content) {
    var hash = 0xcbf29ce484222325;
    for (final unit in content.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x100000001b3) & 0x7fffffffffffffff;
    }
    return '${stat.modified.microsecondsSinceEpoch}:${stat.size}:$hash';
  }

  Future<File?> _resolveContainedFile(String relativePath) async {
    final lexical = path.normalize(
      path.absolute(path.join(root, relativePath)),
    );
    final lexicalRoot = path.normalize(path.absolute(root));
    if (!path.isWithin(lexicalRoot, lexical)) return null;
    try {
      final canonicalRoot = path.normalize(
        path.absolute(await Directory(root).resolveSymbolicLinks()),
      );
      final canonicalTarget = path.normalize(
        path.absolute(await File(lexical).resolveSymbolicLinks()),
      );
      if (!path.isWithin(canonicalRoot, canonicalTarget)) return null;
      return File(canonicalTarget);
    } on FileSystemException {
      return null;
    }
  }

  static bool isSensitivePath(String filePath) {
    final normalized = filePath.replaceAll('\\', '/').toLowerCase();
    final name = path.basename(normalized);
    if (name == '.env' || name.startsWith('.env.')) return true;
    if ({
      '.npmrc',
      '.pypirc',
      'id_rsa',
      'id_ed25519',
      'credentials.json',
      'secrets.yaml',
      'secrets.yml',
      'service-account.json',
      'service_account.json',
    }.contains(name)) {
      return true;
    }
    if (RegExp(
      r'(?:credential|secret|private[-_]?key)',
      caseSensitive: false,
    ).hasMatch(name)) {
      return true;
    }
    return {
      '.pem',
      '.key',
      '.p12',
      '.pfx',
      '.jks',
      '.keystore',
    }.contains(path.extension(name));
  }

  bool _shouldIndex(String filePath) {
    final relative = path.relative(filePath, from: root).replaceAll('\\', '/');
    final components = relative.split('/');
    if (components.any(_ignoredDirectories.contains) ||
        isSensitivePath(relative)) {
      return false;
    }
    return _extensions.contains(path.extension(components.last.toLowerCase()));
  }

  void _indexFile(
    String filePath,
    String content, {
    required String relativeKey,
  }) {
    final relative = relativeKey;
    final extension = path.extension(filePath).toLowerCase();
    final lines = content.split('\n');
    for (var index = 0; index < lines.length; index++) {
      final text = lines[index];
      if (text.trim().isEmpty) continue;
      _lines.add(
        _IndexedLine(
          path: relative,
          line: index + 1,
          text: text,
          searchable: '$relative $text'.toLowerCase(),
        ),
      );
      for (final definition in _definitions(text, extension)) {
        _symbols.add(
          CodeSymbol(
            name: definition.$2,
            kind: definition.$1,
            path: relative,
            line: index + 1,
            preview: text,
          ),
        );
      }
    }
  }

  String _relativeKey(String filePath) =>
      _normalizeRelativeKey(path.relative(filePath, from: root));

  static String _normalizeRelativeKey(String value) {
    final normalized = path.posix.normalize(value.replaceAll('\\', '/'));
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  Iterable<(String, String)> _definitions(String line, String extension) sync* {
    final patterns = <RegExp>[
      if (extension == '.py')
        RegExp(r'^\s*(class|def|async\s+def)\s+([A-Za-z_]\w*)'),
      if (extension == '.go')
        RegExp(r'^\s*(type|func)\s+(?:\([^)]*\)\s*)?([A-Za-z_]\w*)'),
      if (extension == '.rs')
        RegExp(r'^\s*(?:pub\s+)?(struct|enum|trait|fn|mod)\s+([A-Za-z_]\w*)'),
      RegExp(
        r'^\s*(?:export\s+|public\s+|private\s+|protected\s+|internal\s+|static\s+|abstract\s+|sealed\s+|final\s+)*(class|enum|interface|mixin|extension|typedef|record)\s+([A-Za-z_$][\w$]*)',
      ),
      RegExp(
        r'^\s*(?:export\s+|public\s+|private\s+|protected\s+|internal\s+|static\s+|final\s+|const\s+|async\s+)*(?:Future(?:<[^>]+>)?|void|bool|int|double|String|Widget|[A-Z][\w<>?, ]*)\s+([A-Za-z_$][\w$]*)\s*\(',
      ),
      RegExp(
        r'^\s*(?:export\s+)?(?:async\s+)?function\s+([A-Za-z_$][\w$]*)\s*\(',
      ),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(line);
      if (match == null) continue;
      if (match.groupCount >= 2) {
        yield (
          match.group(1)!.replaceAll(RegExp(r'\s+'), ' '),
          match.group(2)!,
        );
      } else {
        yield ('function', match.group(1)!);
      }
      return;
    }
  }

  static double _score(
    String haystack,
    Set<String> exact,
    Set<String> expanded, {
    bool symbol = false,
  }) {
    var score = 0.0;
    for (final token in expanded) {
      if (!haystack.contains(token)) continue;
      score += exact.contains(token) ? 6 : 2;
      if (RegExp(
        '(^|[^a-z0-9_])${RegExp.escape(token)}([^a-z0-9_]|\$)',
      ).hasMatch(haystack)) {
        score += exact.contains(token) ? 5 : 1;
      }
    }
    if (score == 0) return 0;
    if (exact.every(haystack.contains)) score += 8;
    if (symbol) score += 5;
    return score;
  }

  static Set<String> _tokens(String value) => RegExp(r'[A-Za-z0-9_]+')
      .allMatches(value.toLowerCase())
      .map((match) => match.group(0)!)
      .where((token) => token.length >= 2)
      .toSet();
}

class _IndexedLine {
  const _IndexedLine({
    required this.path,
    required this.line,
    required this.text,
    required this.searchable,
  });

  final String path;
  final int line;
  final String text;
  final String searchable;
}
