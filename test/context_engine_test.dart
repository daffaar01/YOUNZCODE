import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kode_agent_desktop/services/code_intelligence_service.dart';
import 'package:kode_agent_desktop/services/context_engine.dart';

void main() {
  test(
    'refreshPaths memperbarui file berubah tanpa kehilangan indeks lain',
    () async {
      final root = await Directory.systemTemp.createTemp('younz-context-');
      addTearDown(() => root.delete(recursive: true));
      final auth = File('${root.path}${Platform.pathSeparator}auth.dart');
      final user = File('${root.path}${Platform.pathSeparator}user.dart');
      await auth.writeAsString('class OldAuth {}\n');
      await user.writeAsString('class UserProfile {}\n');
      final intelligence = CodeIntelligenceService(root.path);

      expect(await intelligence.definition('OldAuth'), isNotNull);
      expect(await intelligence.definition('UserProfile'), isNotNull);
      await auth.writeAsString('class NewAuth {}\n');
      await intelligence.refreshPaths(['auth.dart']);

      expect(await intelligence.definition('OldAuth'), isNull);
      expect(await intelligence.definition('NewAuth'), isNotNull);
      expect(await intelligence.definition('UserProfile'), isNotNull);
    },
  );

  test('refreshPaths paralel tidak menggandakan simbol', () async {
    final root = await Directory.systemTemp.createTemp('younz-context-');
    addTearDown(() => root.delete(recursive: true));
    final file = File('${root.path}${Platform.pathSeparator}auth.dart');
    await file.writeAsString('class AuthService {}\n');
    final intelligence = CodeIntelligenceService(root.path);
    await intelligence.ensureIndexed();

    await Future.wait([
      intelligence.refreshPaths(['auth.dart']),
      intelligence.refreshPaths(['auth.dart']),
      intelligence.refreshPaths(['auth.dart']),
    ]);

    expect(
      intelligence.symbols.where((symbol) => symbol.name == 'AuthService'),
      hasLength(1),
    );
  });

  test('ContextEngine memilih file relevan dengan alasan dan budget', () async {
    final root = await Directory.systemTemp.createTemp('younz-context-');
    addTearDown(() => root.delete(recursive: true));
    await File(
      '${root.path}${Platform.pathSeparator}auth_service.dart',
    ).writeAsString('''class AuthService {
  Future<void> saveToken(String token) async {}
}
''');
    await File(
      '${root.path}${Platform.pathSeparator}unrelated.dart',
    ).writeAsString('class ColorPalette { static const blue = 1; }\n');
    final engine = ContextEngine(
      root.path,
      intelligence: CodeIntelligenceService(root.path),
    );

    final selection = await engine.select(
      'perbaiki penyimpanan token login',
      maxCharacters: 220,
      maxFiles: 3,
    );

    expect(selection.files, isNotEmpty);
    expect(selection.files.first.path, 'auth_service.dart');
    expect(selection.files.first.reason, isNotEmpty);
    expect(selection.totalCharacters, lessThanOrEqualTo(220));
    expect(selection.promptContext, contains('auth_service.dart'));
    expect(selection.promptContext, isNot(contains('ColorPalette')));
  });

  test(
    'ContextEngine menolak file yang diganti symlink setelah diindeks',
    () async {
      final root = await Directory.systemTemp.createTemp('younz-context-');
      final outside = await Directory.systemTemp.createTemp('younz-outside-');
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
        if (await outside.exists()) await outside.delete(recursive: true);
      });
      final indexed = File(
        '${root.path}${Platform.pathSeparator}auth_secret.dart',
      );
      await indexed.writeAsString(
        'class AuthSecret { static const token = "safe"; }\n',
      );
      final external = File(
        '${outside.path}${Platform.pathSeparator}auth_secret.dart',
      );
      await external.writeAsString(
        'class AuthSecret { static const token = "hidden"; }\n',
      );
      final intelligence = CodeIntelligenceService(root.path);
      await intelligence.ensureIndexed();
      await indexed.delete();
      final link = Link(indexed.path);
      try {
        await link.create(external.path);
      } on FileSystemException {
        return;
      }
      final engine = ContextEngine(root.path, intelligence: intelligence);

      final selection = await engine.select('AuthSecret token');

      expect(selection.files, isEmpty);
      expect(selection.promptContext, isNot(contains('hidden')));
    },
  );

  test('ContextEngine tidak pernah membaca environment files', () async {
    final root = await Directory.systemTemp.createTemp('younz-context-');
    addTearDown(() => root.delete(recursive: true));
    await File(
      '${root.path}${Platform.pathSeparator}.env.local',
    ).writeAsString('LOGIN_TOKEN=super-secret-value\n');
    final engine = ContextEngine(root.path);

    final selection = await engine.select('login token');

    expect(selection.promptContext, isNot(contains('super-secret-value')));
    expect(
      selection.files.where((file) => file.path.contains('.env')),
      isEmpty,
    );
  });
}
