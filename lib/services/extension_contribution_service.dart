import '../models/addon.dart';

class ExtensionContributionService {
  const ExtensionContributionService();

  String? resolveCommand(
    String input, {
    required Iterable<Addon> addons,
    required bool workspaceTrusted,
  }) {
    if (!workspaceTrusted) return null;
    final normalized = input.trimLeft();
    if (!normalized.startsWith('/')) return null;
    final delimiter = normalized.indexOf(RegExp(r'\s'));
    final token = delimiter < 0
        ? normalized
        : normalized.substring(0, delimiter);
    final name = token.substring(1).toLowerCase();
    final arguments = delimiter < 0 ? '' : normalized.substring(delimiter + 1);
    DeclarativeCommand? matched;
    for (final addon in addons) {
      if (!addon.enabled || addon.kind != AddonKind.nativePlugin) continue;
      final metadata = addon.metadata as NativePluginMetadata;
      if (!metadata.capabilities.contains('commands.declarative')) continue;
      for (final command in metadata.commands) {
        if (command.name != name) continue;
        if (matched != null) return null;
        matched = command;
      }
    }
    return matched?.render(arguments);
  }
}
