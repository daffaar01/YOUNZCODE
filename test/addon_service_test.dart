import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kode_agent_desktop/models/addon.dart';
import 'package:kode_agent_desktop/services/addon_service.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory temporaryDirectory;
  late Directory sourceDirectory;
  late String addonRoot;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'addon-service-test-',
    );
    sourceDirectory = await Directory(
      p.join(temporaryDirectory.path, 'source'),
    ).create();
    addonRoot = p.join(temporaryDirectory.path, 'managed', 'addons');
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('persisted MCP menolak plaintext header sensitif generik', () {
    expect(
      () => McpServerConfig.fromJson({
        'name': 'legacy',
        'transport': 'http',
        'url': 'https://mcp.example/rpc',
        'headers': {'X-Auth-Token': 'legacy-secret-value'},
      }),
      throwsA(isA<FormatException>()),
    );
  });

  test('load melewati record rusak tanpa menghapus addon lain', () async {
    String importedAt(int day) => DateTime.utc(2026, 7, day).toIso8601String();
    final good = {
      'id': 'good-1',
      'kind': 'skill',
      'name': 'Good',
      'description': '',
      'sourcePath': '/x',
      'installedPath': '/x',
      'importedAt': importedAt(23),
      'enabled': true,
      'metadata': {'fileName': 'SKILL.md'},
    };
    // Unknown kind makes Addon.fromJson throw for this record only.
    final corrupt = {
      'id': 'bad-1',
      'kind': 'a-kind-from-the-future',
      'name': 'Bad',
      'description': '',
      'sourcePath': '/x',
      'installedPath': '/x',
      'importedAt': importedAt(22),
      'metadata': <String, dynamic>{},
    };
    SharedPreferences.setMockInitialValues({
      AddonService.preferencesKey: jsonEncode([corrupt, good]),
    });

    final loaded = await AddonService(addonRoot: addonRoot).load();
    expect(loaded.map((addon) => addon.id), ['good-1']);
  });

  test(
    'imports a skill folder, copies it, and persists typed metadata',
    () async {
      final skillDirectory = await Directory(
        p.join(sourceDirectory.path, 'review-skill'),
      ).create();
      await File(p.join(skillDirectory.path, 'SKILL.md')).writeAsString('''
---
name: Code Reviewer
description: >
  Reviews changes without
  modifying files.
---
# Ignored fallback
''');
      await File(
        p.join(skillDirectory.path, 'notes.txt'),
      ).writeAsString('safe data');
      final service = AddonService(
        addonRoot: addonRoot,
        clock: () => DateTime.utc(2026, 7, 23),
      );

      final addon = await service.importLocal(skillDirectory.path);

      expect(addon.kind, AddonKind.skill);
      expect(addon.name, 'Code Reviewer');
      expect(addon.description, 'Reviews changes without modifying files.');
      expect(addon.metadata, isA<SkillMetadata>());
      expect(p.isWithin(addonRoot, addon.installedPath), isTrue);
      expect(
        await File(p.join(addon.installedPath, 'notes.txt')).readAsString(),
        'safe data',
      );
      expect((await service.load()).single.toJson(), addon.toJson());
    },
  );

  test('installs a bundled skill once and enables it by default', () async {
    final bundledRoot = await Directory(
      p.join(sourceDirectory.path, 'bundled'),
    ).create();
    final graphify = await Directory(
      p.join(bundledRoot.path, 'graphify'),
    ).create();
    await File(p.join(graphify.path, 'SKILL.md')).writeAsString('''
---
name: graphify
description: Knowledge graph skill
---
''');
    await Directory(p.join(graphify.path, 'references')).create();
    await File(
      p.join(graphify.path, 'references', 'query.md'),
    ).writeAsString('query instructions');
    final service = AddonService(addonRoot: addonRoot);

    final first = await service.ensureBundledSkills(bundledRoot.path);
    final second = await service.ensureBundledSkills(bundledRoot.path);

    expect(first, hasLength(1));
    expect(second, hasLength(1));
    expect(second.single.name, 'graphify');
    expect(second.single.enabled, isTrue);
    expect(
      await File(
        p.join(second.single.installedPath, 'references', 'query.md'),
      ).readAsString(),
      'query instructions',
    );
  });

  test('parses Claude and OpenCode MCP stdio/http configurations', () {
    final parsed = AddonService.parseMcpConfig('''
{
  "mcp": {
    "local-tools": {
      "type": "local",
      "command": ["node", "server.js", "--safe"],
      "env": {"MODE": "read-only"}
    },
    "remote-docs": {
      "type": "remote",
      "url": "https://mcp.example.test/api",
      "headers": {"X-Client": "YOUNZCODE"}
    }
  }
}
''');

    expect(parsed.metadata.servers, hasLength(2));
    final local = parsed.metadata.servers.first;
    expect(local.transport, McpTransport.stdio);
    expect(local.command, 'node');
    expect(local.arguments, ['server.js', '--safe']);
    expect(local.environment, {'MODE': 'read-only'});
    final remote = parsed.metadata.servers.last;
    expect(remote.transport, McpTransport.http);
    expect(remote.url, 'https://mcp.example.test/api');
  });

  test('plugin manifest menolak ukuran dan struktur berlebihan', () {
    expect(
      () => AddonService.parsePluginManifest(
        jsonEncode({'name': 'oversized', 'description': 'x' * (256 * 1024)}),
      ),
      throwsA(isA<AddonImportException>()),
    );

    Object nested = 'leaf';
    for (var index = 0; index < 17; index++) {
      nested = {'child': nested};
    }
    expect(
      () => AddonService.parsePluginManifest(
        jsonEncode({'name': 'too-deep', 'metadata': nested}),
      ),
      throwsA(isA<AddonImportException>()),
    );
  });

  test(
    'plugin manifest menolak malformed contributes dan raw name panjang',
    () {
      expect(
        () => AddonService.parsePluginManifest(
          '{"name":"safe","contributes":"invalid"}',
        ),
        throwsA(isA<AddonImportException>()),
      );
      expect(
        () => AddonService.parsePluginManifest(
          jsonEncode({'name': 'x' * 257, 'displayName': 'short'}),
        ),
        throwsA(isA<AddonImportException>()),
      );
    },
  );

  test('plugin declarative membutuhkan capability eksplisit', () {
    expect(
      () => AddonService.parsePluginManifest(
        '{"name":"unsafe","instructions":"Read the workspace"}',
      ),
      throwsA(isA<AddonImportException>()),
    );
    expect(
      () => AddonService.parsePluginManifest(
        '{"name":"unsafe","capabilities":["process.execute"]}',
      ),
      throwsA(isA<AddonImportException>()),
    );

    final parsed = AddonService.parsePluginManifest('''
{
  "name":"safe-review",
  "apiVersion":"1",
  "capabilities":["agent.instructions"],
  "instructions":"Review without modifying files"
}
''');
    expect(parsed.metadata.apiVersion, '1');
    expect(parsed.metadata.capabilities, {'agent.instructions'});
    expect(parsed.metadata.instructions, 'Review without modifying files');
  });

  test('legacy plugin instructions dimigrasikan tetapi dinonaktifkan', () {
    final legacy = <String, dynamic>{
      'id': 'legacy-plugin',
      'kind': 'nativePlugin',
      'name': 'Legacy Plugin',
      'description': '',
      'sourcePath': 'source',
      'installedPath': 'installed',
      'importedAt': DateTime.utc(2026).toIso8601String(),
      'enabled': true,
      'metadata': {
        'manifest': {'name': 'legacy-plugin', 'prompt': 'Legacy instructions'},
      },
    };

    final restored = Addon.fromJson(legacy);
    final metadata = restored.metadata as NativePluginMetadata;

    expect(restored.enabled, isFalse);
    expect(metadata.capabilities, {'agent.instructions'});
    expect(metadata.instructions, 'Legacy instructions');
    expect(metadata.manifest, {'name': 'legacy-plugin'});
    expect(metadata.manifest, isNot(contains('prompt')));
  });

  test(
    'legacy plugin restore menolak manifest oversized dan terlalu dalam',
    () {
      Map<String, dynamic> legacyWithManifest(Map<String, dynamic> manifest) =>
          {
            'id': 'legacy-plugin',
            'kind': 'nativePlugin',
            'name': 'Legacy Plugin',
            'description': '',
            'sourcePath': 'source',
            'installedPath': 'installed',
            'importedAt': DateTime.utc(2026).toIso8601String(),
            'enabled': true,
            'metadata': {'manifest': manifest},
          };

      expect(
        () => Addon.fromJson(
          legacyWithManifest({
            'name': 'legacy',
            'prompt': 'Legacy instructions',
            'padding': 'x' * (256 * 1024),
          }),
        ),
        throwsA(isA<FormatException>()),
      );

      Object nested = 'leaf';
      for (var index = 0; index < 17; index++) {
        nested = {'child': nested};
      }
      expect(
        () => Addon.fromJson(
          legacyWithManifest({
            'name': 'legacy',
            'prompt': 'Legacy instructions',
            'metadata': nested,
          }),
        ),
        throwsA(isA<FormatException>()),
      );
    },
  );

  test('plugin command description memiliki parse restore boundary sama', () {
    final description = 'd' * 4001;
    expect(
      () => AddonService.parsePluginManifest(
        jsonEncode({
          'name': 'description-boundary',
          'capabilities': ['commands.declarative'],
          'contributes': {
            'commands': [
              {
                'name': 'describe-code',
                'description': description,
                'prompt': 'Describe {{args}}',
              },
            ],
          },
        }),
      ),
      throwsA(isA<AddonImportException>()),
    );
  });

  test('restore plugin menolak capability persistence yang dimanipulasi', () {
    final json = Addon(
      id: 'plugin',
      kind: AddonKind.nativePlugin,
      name: 'Plugin',
      description: '',
      sourcePath: 'source',
      installedPath: 'installed',
      importedAt: DateTime(2026),
      metadata: const NativePluginMetadata(manifest: {'name': 'plugin'}),
    ).toJson();
    final metadata = json['metadata']! as Map<String, dynamic>;
    metadata['capabilities'] = ['process.execute'];

    expect(() => Addon.fromJson(json), throwsFormatException);
  });

  test('plugin declarative memvalidasi slash command capability', () {
    expect(
      () => AddonService.parsePluginManifest('''
{
  "name":"unsafe-command",
  "apiVersion":"1",
  "capabilities":["commands.declarative"],
  "contributes":{"commands":[{"name":"help","prompt":"override"}]}
}
'''),
      throwsA(isA<AddonImportException>()),
    );

    final parsed = AddonService.parsePluginManifest('''
{
  "name":"safe-command",
  "apiVersion":"1",
  "capabilities":["commands.declarative"],
  "contributes":{"commands":[{
    "name":"explain-code",
    "description":"Explain selected code",
    "prompt":"Explain this request safely: {{args}}"
  }]}
}
''');
    expect(parsed.metadata.commands, hasLength(1));
    expect(parsed.metadata.commands.single.name, 'explain-code');
    expect(
      parsed.metadata.commands.single.render('lib/main.dart'),
      'Explain this request safely: lib/main.dart',
    );
  });

  test('parses native plugin manifest and VSIX filename metadata', () {
    final plugin = AddonService.parsePluginManifest('''
{"name":"native.git","displayName":"Native Git","version":"1.2.0","main":"bin/plugin.exe"}
''');
    expect(plugin.name, 'Native Git');
    expect(plugin.metadata.version, '1.2.0');
    expect(plugin.metadata.entryPoint, 'bin/plugin.exe');

    final vsix = AddonService.parseVsixFilename(
      'acme.code-helper-2.4.1-beta.2.vsix',
    );
    expect(vsix.metadata.publisher, 'acme');
    expect(vsix.metadata.extensionName, 'code-helper');
    expect(vsix.metadata.version, '2.4.1-beta.2');
  });

  test('MCP HTTP credentials wajib memakai headerReferences', () {
    expect(
      () => AddonService.parseMcpConfig('''
{"mcpServers":{"remote":{"url":"https://mcp.example/rpc","headers":{"Authorization":"Bearer plaintext"}}}}
'''),
      throwsA(isA<AddonImportException>()),
    );
    final parsed = AddonService.parseMcpConfig('''
{"mcpServers":{"remote":{"url":"https://mcp.example/rpc","headerReferences":{"Authorization":"mcp.remote.authorization"}}}}
''');
    expect(
      parsed.metadata.servers.single.headerReferences['Authorization'],
      'mcp.remote.authorization',
    );
    expect(parsed.metadata.toJson().toString(), isNot(contains('plaintext')));
  });

  test('rejects invalid HTTP MCP URLs and managed-root imports', () async {
    expect(
      () => AddonService.parseMcpConfig(
        '{"mcpServers":{"bad":{"url":"file:///tmp/server"}}}',
      ),
      throwsA(isA<AddonImportException>()),
    );

    final managedSkill = await Directory(
      p.join(addonRoot, 'manual'),
    ).create(recursive: true);
    await File(
      p.join(managedSkill.path, 'SKILL.md'),
    ).writeAsString('# Unsafe source');
    final service = AddonService(addonRoot: addonRoot);
    await expectLater(
      service.importLocal(managedSkill.path),
      throwsA(isA<AddonImportException>()),
    );
  });

  test('toggles and removes persisted addons and copied files', () async {
    final vsix = File(p.join(sourceDirectory.path, 'acme.helper-1.0.0.vsix'));
    await vsix.writeAsBytes([0, 1, 2, 3]);
    final service = AddonService(addonRoot: addonRoot);
    final imported = await service.importLocal(vsix.path);

    final disabled = await service.setEnabled(imported.id, false);
    expect(disabled.enabled, isFalse);
    expect((await service.load()).single.enabled, isFalse);

    await service.remove(imported.id);
    expect(await service.load(), isEmpty);
    expect(await File(imported.installedPath).exists(), isFalse);
  });
}
