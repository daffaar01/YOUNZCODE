class SecretScanner {
  static final _patterns = <(String, RegExp)>[
    // Full PEM block first so the entire key body is masked, not just the
    // header line. A truncated block (no END marker) is caught by the fallback.
    (
      'private key',
      RegExp(
        r'-----BEGIN (?:[A-Z0-9 ]+ )?PRIVATE KEY-----[\s\S]*?-----END (?:[A-Z0-9 ]+ )?PRIVATE KEY-----',
      ),
    ),
    ('private key', RegExp(r'-----BEGIN (?:[A-Z0-9 ]+ )?PRIVATE KEY-----')),
    (
      'JWT',
      RegExp(r'\beyJ[a-zA-Z0-9_-]{8,}\.[a-zA-Z0-9_-]{8,}\.[a-zA-Z0-9_-]{8,}\b'),
    ),
    ('GitHub token', RegExp(r'\bgh[pousr]_[A-Za-z0-9_]{20,}\b')),
    // Fine-grained personal access tokens use the github_pat_ prefix.
    ('GitHub token', RegExp(r'\bgithub_pat_[A-Za-z0-9_]{20,}\b')),
    ('OpenAI key', RegExp(r'\bsk-[A-Za-z0-9_-]{20,}\b')),
    ('npm token', RegExp(r'\bnpm_[A-Za-z0-9]{20,}\b')),
    ('Google API key', RegExp(r'\bAIza[A-Za-z0-9_-]{30,}\b')),
    (
      'authorization',
      RegExp(
        r'authorization\s*:\s*(?:bearer|basic)\s+[A-Za-z0-9+/_=.-]{12,}',
        caseSensitive: false,
      ),
    ),
    (
      'credential URI',
      RegExp(r'https?://[^\s/:@]+:[^\s/@]{8,}@[^\s/]+', caseSensitive: false),
    ),
    (
      'cookie',
      RegExp(r'(?:set-)?cookie\s*:\s*[^\r\n]{12,}', caseSensitive: false),
    ),
    ('Slack token', RegExp(r'\bxox[baprs]-[A-Za-z0-9-]{20,}\b')),
    // Long-term (AKIA) and temporary/session (ASIA) AWS access key ids.
    ('AWS key', RegExp(r'\b(?:AKIA|ASIA)[0-9A-Z]{16}\b')),
    // Generic key/value credentials. No leading word boundary so compound
    // keys (db_password) are caught, and an optional closing quote is allowed
    // before the separator so JSON-quoted keys ("password": "…") match too.
    (
      'credential',
      RegExp(
        r'''(?:api[_-]?key|secret|token|password|passwd|database[_-]?url|private[_-]?[a-z0-9_-]*token[a-z0-9_-]*|session[_-]?(?:value|token|secret))["]?'?\s*[:=]\s*["]?'?([^\s"',;]{8,})''',
        caseSensitive: false,
      ),
    ),
  ];

  static String redact(String content) {
    var result = content;
    for (final (label, pattern) in _patterns) {
      result = result.replaceAllMapped(pattern, (_) => '[REDACTED $label]');
    }
    return result;
  }

  static bool containsSecret(String content) =>
      _patterns.any((item) => item.$2.hasMatch(content));
}
