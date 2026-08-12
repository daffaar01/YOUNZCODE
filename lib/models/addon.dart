import 'dart:convert';

enum AddonKind { nativePlugin, skill, mcpServer, vsix }

enum McpTransport { stdio, http }

const pluginReservedCommands = {
  'download',
  'graphify',
  'agents',
  'mcp',
  'review',
  'fork',
  'model',
  'models',
  'usage',
  'share',
  'open',
  'skill',
  'help',
  'new',
  'clear',
  'terminal',
  'explorer',
  'editor',
  'settings',
  'history',
  'addons',
  'search',
  'symbol',
  'images',
  'browser',
  'notifications',
  'goal',
  'plan',
  'build',
  'update',
  'update-status',
};

sealed class AddonMetadata {
  const AddonMetadata();

  Map<String, dynamic> toJson();
}

class DeclarativeCommand {
  const DeclarativeCommand({
    required this.name,
    required this.description,
    required this.prompt,
  });

  factory DeclarativeCommand.fromJson(Map<String, dynamic> json) =>
      DeclarativeCommand(
        name: json['name'] as String,
        description: json['description'] as String? ?? '',
        prompt: json['prompt'] as String,
      );

  final String name;
  final String description;
  final String prompt;

  String render(String arguments) => prompt.replaceAll('{{args}}', arguments);

  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    'prompt': prompt,
  };
}

class NativePluginMetadata extends AddonMetadata {
  const NativePluginMetadata({
    required this.manifest,
    this.version,
    this.entryPoint,
    this.apiVersion = '1',
    this.capabilities = const {},
    this.instructions,
    this.commands = const [],
  });

  final Map<String, dynamic> manifest;
  final String? version;
  final String? entryPoint;
  final String apiVersion;
  final Set<String> capabilities;
  final String? instructions;
  final List<DeclarativeCommand> commands;

  @override
  Map<String, dynamic> toJson() => {
    'manifest': manifest,
    if (version != null) 'version': version,
    if (entryPoint != null) 'entryPoint': entryPoint,
    'apiVersion': apiVersion,
    if (capabilities.isNotEmpty) 'capabilities': capabilities.toList()..sort(),
    if (instructions != null) 'instructions': instructions,
    if (commands.isNotEmpty)
      'commands': commands.map((command) => command.toJson()).toList(),
  };
}

class SkillMetadata extends AddonMetadata {
  const SkillMetadata({required this.fileName});

  final String fileName;

  @override
  Map<String, dynamic> toJson() => {'fileName': fileName};
}

class McpServerConfig {
  const McpServerConfig({
    required this.name,
    required this.transport,
    this.command,
    this.arguments = const [],
    this.environment = const {},
    this.url,
    this.headers = const {},
  });

  factory McpServerConfig.fromJson(Map<String, dynamic> json) =>
      McpServerConfig(
        name: json['name'] as String,
        transport: McpTransport.values.byName(json['transport'] as String),
        command: json['command'] as String?,
        arguments: _stringList(json['arguments']),
        environment: _stringMap(json['environment']),
        url: json['url'] as String?,
        headers: _stringMap(json['headers']),
      );

  final String name;
  final McpTransport transport;
  final String? command;
  final List<String> arguments;
  final Map<String, String> environment;
  final String? url;
  final Map<String, String> headers;

  Map<String, dynamic> toJson() => {
    'name': name,
    'transport': transport.name,
    if (command != null) 'command': command,
    if (arguments.isNotEmpty) 'arguments': arguments,
    if (environment.isNotEmpty) 'environment': environment,
    if (url != null) 'url': url,
    if (headers.isNotEmpty) 'headers': headers,
  };
}

class McpMetadata extends AddonMetadata {
  const McpMetadata({required this.servers});

  final List<McpServerConfig> servers;

  @override
  Map<String, dynamic> toJson() => {
    'servers': servers.map((server) => server.toJson()).toList(),
  };
}

class VsixMetadata extends AddonMetadata {
  const VsixMetadata({
    required this.extensionName,
    this.publisher,
    this.version,
  });

  final String extensionName;
  final String? publisher;
  final String? version;

  @override
  Map<String, dynamic> toJson() => {
    'extensionName': extensionName,
    if (publisher != null) 'publisher': publisher,
    if (version != null) 'version': version,
  };
}

class Addon {
  const Addon({
    required this.id,
    required this.kind,
    required this.name,
    required this.description,
    required this.sourcePath,
    required this.installedPath,
    required this.importedAt,
    required this.metadata,
    this.enabled = true,
  });

  factory Addon.fromJson(Map<String, dynamic> json) {
    final kind = AddonKind.values.byName(json['kind'] as String);
    final metadata = Map<String, dynamic>.from(json['metadata'] as Map);
    final legacyNativePlugin =
        kind == AddonKind.nativePlugin && _isLegacyNativePlugin(metadata);
    return Addon(
      id: json['id'] as String,
      kind: kind,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      sourcePath: json['sourcePath'] as String,
      installedPath: json['installedPath'] as String,
      importedAt: DateTime.parse(json['importedAt'] as String),
      enabled: legacyNativePlugin ? false : json['enabled'] as bool? ?? true,
      metadata: switch (kind) {
        AddonKind.nativePlugin => _restoreNativePlugin(metadata),
        AddonKind.skill => SkillMetadata(
          fileName: metadata['fileName'] as String,
        ),
        AddonKind.mcpServer => McpMetadata(
          servers: (metadata['servers'] as List)
              .map(
                (server) => McpServerConfig.fromJson(
                  Map<String, dynamic>.from(server as Map),
                ),
              )
              .toList(),
        ),
        AddonKind.vsix => VsixMetadata(
          extensionName: metadata['extensionName'] as String,
          publisher: metadata['publisher'] as String?,
          version: metadata['version'] as String?,
        ),
      },
    );
  }

  final String id;
  final AddonKind kind;
  final String name;
  final String description;
  final String sourcePath;
  final String installedPath;
  final DateTime importedAt;
  final AddonMetadata metadata;
  final bool enabled;

  Addon copyWith({bool? enabled}) => Addon(
    id: id,
    kind: kind,
    name: name,
    description: description,
    sourcePath: sourcePath,
    installedPath: installedPath,
    importedAt: importedAt,
    metadata: metadata,
    enabled: enabled ?? this.enabled,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'name': name,
    'description': description,
    'sourcePath': sourcePath,
    'installedPath': installedPath,
    'importedAt': importedAt.toIso8601String(),
    'enabled': enabled,
    'metadata': metadata.toJson(),
  };
}

NativePluginMetadata _restoreNativePlugin(Map<String, dynamic> metadata) {
  const allowed = {'agent.instructions', 'commands.declarative'};
  final legacy = _isLegacyNativePlugin(metadata);
  final manifest = Map<String, dynamic>.from(metadata['manifest'] as Map);
  _validatePersistedManifest(manifest);
  final canonicalName = manifest['name']?.toString().trim();
  if (canonicalName == null ||
      canonicalName.isEmpty ||
      canonicalName.length > 256) {
    throw const FormatException('Persisted plugin name tidak valid.');
  }
  final apiVersion = metadata['apiVersion'] as String? ?? '1';
  final rawCapabilities = metadata['capabilities'];
  if (rawCapabilities != null &&
      (rawCapabilities is! List ||
          rawCapabilities.any((value) => value is! String || value.isEmpty))) {
    throw const FormatException('Persisted plugin capabilities tidak valid.');
  }
  final capabilities = legacy
      ? <String>{'agent.instructions'}
      : (rawCapabilities as List? ?? const []).cast<String>().toSet();
  final instructions = legacy
      ? (manifest['instructions'] ?? manifest['prompt']) as String?
      : metadata['instructions'] as String?;
  final rawCommands = metadata['commands'];
  if (rawCommands != null &&
      (rawCommands is! List || rawCommands.any((value) => value is! Map))) {
    throw const FormatException('Persisted plugin commands tidak valid.');
  }
  final commands = (rawCommands as List? ?? const [])
      .map(
        (value) => DeclarativeCommand.fromJson(
          Map<String, dynamic>.from(value as Map),
        ),
      )
      .toList();
  if (apiVersion != '1' ||
      capabilities.difference(allowed).isNotEmpty ||
      (instructions != null &&
          (!capabilities.contains('agent.instructions') ||
              instructions.length > 12000)) ||
      commands.length > 32 ||
      (commands.isNotEmpty && !capabilities.contains('commands.declarative'))) {
    throw const FormatException('Persisted plugin metadata tidak valid.');
  }
  final names = <String>{};
  for (final command in commands) {
    if (!RegExp(r'^[a-z][a-z0-9-]{1,31}$').hasMatch(command.name) ||
        pluginReservedCommands.contains(command.name) ||
        !names.add(command.name) ||
        command.prompt.isEmpty ||
        command.prompt.length > 4000 ||
        command.description.length > 4000) {
      throw const FormatException('Persisted plugin command tidak valid.');
    }
  }
  return NativePluginMetadata(
    manifest: {'name': canonicalName},
    version: metadata['version'] as String?,
    entryPoint: metadata['entryPoint'] as String?,
    apiVersion: apiVersion,
    capabilities: Set.unmodifiable(capabilities),
    instructions: instructions,
    commands: List.unmodifiable(commands),
  );
}

void _validatePersistedManifest(Map<String, dynamic> manifest) {
  if (utf8.encode(jsonEncode(manifest)).length > 256 * 1024) {
    throw const FormatException('Persisted plugin manifest terlalu besar.');
  }
  final pending = <(Object?, int)>[(manifest, 0)];
  var nodes = 0;
  while (pending.isNotEmpty) {
    final (value, depth) = pending.removeLast();
    nodes++;
    if (nodes > 4096 || depth > 16) {
      throw const FormatException(
        'Persisted plugin manifest terlalu kompleks.',
      );
    }
    if (value is Map) {
      for (final entry in value.entries) {
        pending.add((entry.key, depth + 1));
        pending.add((entry.value, depth + 1));
      }
    } else if (value is List) {
      for (final item in value) {
        pending.add((item, depth + 1));
      }
    }
  }
}

bool _isLegacyNativePlugin(Map<String, dynamic> metadata) {
  if (metadata.containsKey('apiVersion') ||
      metadata.containsKey('capabilities') ||
      metadata.containsKey('instructions')) {
    return false;
  }
  final manifest = metadata['manifest'];
  return manifest is Map &&
      (manifest['instructions'] is String || manifest['prompt'] is String);
}

List<String> _stringList(Object? value) =>
    (value as List? ?? const []).map((item) => item.toString()).toList();

Map<String, String> _stringMap(Object? value) => (value as Map? ?? const {})
    .map((key, item) => MapEntry(key.toString(), item.toString()));
