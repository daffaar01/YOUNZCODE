import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat_session.dart';
import 'secret_scanner.dart';

class ChatSessionStore {
  static const _sessionsKey = 'chat_sessions_v1';
  Future<void> _pendingSave = Future.value();

  Future<List<ChatSession>> load() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_sessionsKey);
    if (encoded == null || encoded.isEmpty) return [];
    final List<dynamic> values;
    try {
      values = jsonDecode(encoded) as List;
    } catch (_) {
      return [];
    }
    final sessions = <ChatSession>[];
    for (final value in values) {
      try {
        sessions.add(
          ChatSession.fromJson(Map<String, dynamic>.from(value as Map)),
        );
      } catch (_) {
        // Skip a single corrupt record rather than discarding the whole
        // history (which the next save() would then overwrite permanently).
      }
    }
    sessions.sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    return sessions;
  }

  Future<void> save(List<ChatSession> sessions) async {
    final ordered = [...sessions]
      ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    final snapshot = jsonEncode(
      ordered.take(50).map(_safeCheckpointJson).toList(growable: false),
    );
    final save = _pendingSave.then((_) async {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_sessionsKey, snapshot);
    });
    _pendingSave = save.catchError((_) {});
    await save;
  }

  Map<String, dynamic> _safeCheckpointJson(ChatSession session) => {
    'id': session.id,
    'workspace': session.workspace,
    'updatedAt': session.updatedAt.toIso8601String(),
    'entries': session.entries
        .where((entry) => entry.role.name != 'tool')
        .map(
          (entry) => {
            'role': entry.role.name,
            'content': SecretScanner.redact(entry.content),
          },
        )
        .toList(growable: false),
    'agentMessages': session.entries
        .where(
          (entry) =>
              entry.role.name == 'user' || entry.role.name == 'assistant',
        )
        .map(
          (entry) => {
            'role': entry.role.name,
            'content': SecretScanner.redact(entry.content),
          },
        )
        .toList(growable: false),
    if (session.goal != null)
      'goal': {
        ...session.goal!.toJson(),
        'objective': SecretScanner.redact(session.goal!.objective),
        if (session.goal!.lastDetail.isNotEmpty)
          'lastDetail': SecretScanner.redact(session.goal!.lastDetail),
      },
    if (session.taskGraph != null)
      'taskGraph': _safeTaskGraph(session.taskGraph!.toJson()),
  };

  String _redactBounded(String value) {
    final redacted = SecretScanner.redact(value);
    return redacted.length <= 12000 ? redacted : redacted.substring(0, 12000);
  }

  Map<String, dynamic> _safeTaskGraph(Map<String, dynamic> graph) => {
    'id': graph['id'],
    'objective': _redactBounded(graph['objective'] as String? ?? ''),
    'nodes': (graph['nodes'] as List? ?? const [])
        .take(64)
        .map((raw) {
          final node = Map<String, dynamic>.from(raw as Map);
          return {
            'id': node['id'],
            'title': _redactBounded(node['title'] as String? ?? ''),
            'dependencies': node['dependencies'],
            'status': node['status'],
            if (node['detail'] is String)
              'detail': _redactBounded(node['detail'] as String),
            if (node['agentId'] is String)
              'agentId': _redactBounded(node['agentId'] as String),
            if (node['worktree'] is String)
              'worktree': _redactBounded(node['worktree'] as String),
            'attempt': node['attempt'],
            'artifacts': (node['artifacts'] as List? ?? const [])
                .take(32)
                .map((rawArtifact) {
                  final artifact = Map<String, dynamic>.from(
                    rawArtifact as Map,
                  );
                  return {
                    'kind': _redactBounded(artifact['kind'] as String? ?? ''),
                    'label': _redactBounded(artifact['label'] as String? ?? ''),
                    'value': _redactBounded(artifact['value'] as String? ?? ''),
                  };
                })
                .toList(growable: false),
          };
        })
        .toList(growable: false),
  };
}
