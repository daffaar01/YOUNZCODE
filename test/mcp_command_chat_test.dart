import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kode_agent_desktop/models/addon.dart';

void main() {
  test('MCP kosong memberi petunjuk chat tanpa mencampur skill', () {
    final graphify = Addon(
      id: 'skill-1',
      kind: AddonKind.skill,
      name: 'graphify',
      description: 'Codebase graph skill',
      sourcePath: 'source',
      installedPath: 'installed',
      importedAt: DateTime.utc(2026),
      metadata: const SkillMetadata(fileName: 'SKILL.md'),
    );

    final message = formatMcpSummaryForChat([graphify]);

    expect(message, contains('Belum ada MCP server yang diimpor'));
    expect(message, contains('ADD-ONS > IMPORT FILE'));
    expect(message, isNot(contains('graphify')));
  });

  test('ringkasan MCP hanya menampilkan server dan transport', () {
    final addon = Addon(
      id: 'mcp-1',
      kind: AddonKind.mcpServer,
      name: 'Remote tools',
      description: 'Test MCP',
      sourcePath: 'source',
      installedPath: 'installed',
      importedAt: DateTime.utc(2026),
      metadata: const McpMetadata(
        servers: [
          McpServerConfig(
            name: 'remote-docs',
            transport: McpTransport.http,
            url: 'https://mcp.example/api',
          ),
        ],
      ),
    );

    final message = formatMcpSummaryForChat([addon]);

    expect(message, contains('MCP SERVERS — 1'));
    expect(message, contains('✅ remote-docs'));
    expect(message, contains('HTTP'));
    expect(message, isNot(contains('https://mcp.example/api')));
  });

  test('/mcp route tidak membuka Add-on Manager', () {
    final source = File(
      'lib/app/command_workflow.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    expect(
      source,
      contains("case '/mcp':\n        _showMcpSummary(argument);"),
    );
    final start = source.indexOf('void _showMcpSummary(');
    final end = source.indexOf('void _showAddonSummary(', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final body = source.substring(start, end);
    expect(body, contains('_addLocalResponse('));
    expect(body, isNot(contains('_openAddonManager')));
  });
}
