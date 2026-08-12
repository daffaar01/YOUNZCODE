import 'package:flutter_test/flutter_test.dart';
import 'package:kode_agent_desktop/models/addon.dart';
import 'package:kode_agent_desktop/services/extension_contribution_service.dart';

void main() {
  Addon plugin({required bool enabled}) => Addon(
    id: 'plugin-1',
    kind: AddonKind.nativePlugin,
    name: 'Safe plugin',
    description: '',
    sourcePath: 'source',
    installedPath: 'installed',
    importedAt: DateTime.utc(2026, 8, 12),
    enabled: enabled,
    metadata: const NativePluginMetadata(
      manifest: {},
      capabilities: {'commands.declarative'},
      commands: [
        DeclarativeCommand(
          name: 'explain-code',
          description: 'Explain code',
          prompt: 'Explain safely: {{args}}',
        ),
      ],
    ),
  );

  test('resolver hanya menjalankan command deklaratif aktif dan trusted', () {
    final service = ExtensionContributionService();

    expect(
      service.resolveCommand(
        '/explain-code lib/main.dart',
        addons: [plugin(enabled: true)],
        workspaceTrusted: true,
      ),
      'Explain safely: lib/main.dart',
    );
    expect(
      service.resolveCommand(
        '/explain-code  first\tsecond\nthird',
        addons: [plugin(enabled: true)],
        workspaceTrusted: true,
      ),
      'Explain safely:  first\tsecond\nthird',
    );
    expect(
      service.resolveCommand(
        '/explain-code lib/main.dart',
        addons: [plugin(enabled: false)],
        workspaceTrusted: true,
      ),
      isNull,
    );
    expect(
      service.resolveCommand(
        '/explain-code lib/main.dart',
        addons: [plugin(enabled: true)],
        workspaceTrusted: false,
      ),
      isNull,
    );
  });
}
