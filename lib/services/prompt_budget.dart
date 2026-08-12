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
}
