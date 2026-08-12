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
    final kept = <Map<String, dynamic>>[];
    if (copied.first['role'] == 'system') kept.add(copied.first);
    for (var index = copied.length - 1; index >= 0; index--) {
      final candidate = copied[index];
      if (identical(candidate, copied.first) && kept.isNotEmpty) continue;
      final insertion = kept.isNotEmpty && kept.first['role'] == 'system'
          ? 1
          : 0;
      final trial = [...kept]..insert(insertion, candidate);
      if (messageCharacters(trial) <= maxCharacters) {
        kept
          ..clear()
          ..addAll(trial);
      }
    }
    while (kept.isNotEmpty && messageCharacters(kept) > maxCharacters) {
      if (kept.length > 1) {
        kept.removeAt(kept.first['role'] == 'system' ? 1 : 0);
        continue;
      }
      final content = kept.single['content'];
      if (content is! String || content.isEmpty) return const [];
      final overflow = messageCharacters(kept) - maxCharacters;
      kept.single['content'] = content.substring(
        0,
        (content.length - overflow).clamp(0, content.length),
      );
    }
    return kept;
  }
}
