import 'dart:convert';

class PromptBudget {
  PromptBudget({required this.maxCharacters}) : assert(maxCharacters >= 0);

  final int maxCharacters;
  final StringBuffer _buffer = StringBuffer();

  int get length => _buffer.length;
  int get remaining => maxCharacters - length;
  bool get isFull => remaining <= 0;

  void writeInitial(String value) {
    if (_buffer.isNotEmpty) {
      throw StateError('Initial prompt hanya boleh ditulis sekali.');
    }
    appendText(value);
  }

  void appendText(String value) {
    if (remaining <= 0 || value.isEmpty) return;
    _buffer.write(
      value.length <= remaining ? value : value.substring(0, remaining),
    );
  }

  bool appendBlock({
    required String header,
    required String content,
    String truncationMarker = '',
  }) {
    if (header.length > remaining) return false;
    final blockLength = header.length + content.length;
    if (blockLength <= remaining) {
      _buffer
        ..write(header)
        ..write(content);
      return true;
    }
    if (header.length + truncationMarker.length > remaining) return false;
    final contentBudget = remaining - header.length - truncationMarker.length;
    _buffer
      ..write(header)
      ..write(content.substring(0, contentBudget))
      ..write(truncationMarker);
    return true;
  }

  @override
  String toString() => _buffer.toString();

  static int messageCharacters(List<Map<String, dynamic>> messages) =>
      jsonEncode(messages).length;

  /// Keeps the system instruction and newest complete messages, dropping old
  /// history before truncating the newest content as a fail-safe.
  static List<Map<String, dynamic>> constrainMessages(
    List<Map<String, dynamic>> messages, {
    int maxCharacters = 320000,
  }) {
    if (maxCharacters <= 2 || messages.isEmpty) return const [];
    final copied = messages
        .map((message) => Map<String, dynamic>.from(message))
        .toList();
    if (messageCharacters(copied) <= maxCharacters) return copied;
    final newestUserIndex = copied.lastIndexWhere(
      (message) => message['role'] == 'user',
    );
    if (newestUserIndex < 0) {
      return _constrainWithoutRequiredUser(copied, maxCharacters);
    }

    final newestUser = copied[newestUserIndex];
    final kept = <Map<String, dynamic>>[];
    final hasSystem = copied.first['role'] == 'system' && newestUserIndex != 0;
    if (hasSystem) kept.add(copied.first);
    kept.add(newestUser);

    final originalNewestContent = newestUser['content'];
    if (!_truncateNewestUserToFit(kept, maxCharacters)) {
      if (!hasSystem) return const [];
      kept.removeAt(0);
      newestUser['content'] = originalNewestContent;
      if (!_truncateNewestUserToFit(kept, maxCharacters)) return const [];
    }

    for (var index = newestUserIndex - 1; index >= 0; index--) {
      if (hasSystem && index == 0) continue;
      final trial = [...kept];
      final insertion = hasSystem ? 1 : 0;
      trial.insert(insertion, copied[index]);
      if (messageCharacters(trial) <= maxCharacters) {
        kept
          ..clear()
          ..addAll(trial);
      }
    }
    return kept;
  }

  static bool _truncateNewestUserToFit(
    List<Map<String, dynamic>> messages,
    int maxCharacters,
  ) {
    if (messageCharacters(messages) <= maxCharacters) return true;
    final message = messages.last;
    final content = message['content'];
    if (content is! String) return false;
    var low = 0;
    var high = content.length;
    while (low < high) {
      final middle = (low + high + 1) ~/ 2;
      message['content'] = content.substring(0, middle);
      if (messageCharacters(messages) <= maxCharacters) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }
    message['content'] = content.substring(0, low);
    return messageCharacters(messages) <= maxCharacters;
  }

  static List<Map<String, dynamic>> _constrainWithoutRequiredUser(
    List<Map<String, dynamic>> messages,
    int maxCharacters,
  ) {
    final kept = <Map<String, dynamic>>[];
    for (var index = messages.length - 1; index >= 0; index--) {
      final trial = [messages[index], ...kept];
      if (messageCharacters(trial) <= maxCharacters) {
        kept
          ..clear()
          ..addAll(trial);
      }
    }
    return kept;
  }
}
