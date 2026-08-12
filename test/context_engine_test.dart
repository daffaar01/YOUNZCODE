import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kode_agent_desktop/services/code_intelligence_service.dart';
import 'package:kode_agent_desktop/services/context_engine.dart';
import 'package:kode_agent_desktop/services/secret_scanner.dart';

void main() {
  test('SecretScanner menolak credential URI pendek dan username kosong', () {
    for (final uri in [
      'postgresql://user:x@db.internal/app',
      'redis://:x@cache.internal:6379/0',
      'mongodb+srv://user:***@cluster.example/app',
      'postgresql://user%3Ax@db.internal/app',
    ]) {
      expect(SecretScanner.containsSecret(uri), isTrue, reason: uri);
    }
  });

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

  test('refreshPaths tidak mengindeks symlink di luar workspace', () async {
    final root = await Directory.systemTemp.createTemp('younz-context-');
    final outside = await Directory.systemTemp.createTemp('younz-outside-');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
      if (await outside.exists()) await outside.delete(recursive: true);
    });
    final external = File(
      '${outside.path}${Platform.pathSeparator}external.dart',
    );
    await external.writeAsString('class ExternalCredential {}\n');
    final link = Link('${root.path}${Platform.pathSeparator}linked.dart');
    try {
      await link.create(external.path);
    } on FileSystemException {
      return;
    }
    final intelligence = CodeIntelligenceService(root.path);

    await intelligence.refreshPaths(['linked.dart']);

    expect(await intelligence.definition('ExternalCredential'), isNull);
  });

  test(
    'refreshExternalChanges mendeteksi same-size content dengan mtime lama',
    () async {
      final root = await Directory.systemTemp.createTemp('younz-context-');
      addTearDown(() => root.delete(recursive: true));
      final file = File('${root.path}${Platform.pathSeparator}model.dart');
      await file.writeAsString('class OldName {}\n');
      final originalModified = (await file.stat()).modified;
      final intelligence = CodeIntelligenceService(root.path);
      await intelligence.ensureIndexed();

      await file.writeAsString('class NewName {}\n');
      await file.setLastModified(originalModified);
      await intelligence.refreshExternalChanges();

      expect(await intelligence.definition('OldName'), isNull);
      expect(await intelligence.definition('NewName'), isNotNull);
    },
  );

  test(
    'ContextEngine fail-closed tanpa membaca file workspace otomatis',
    () async {
      final root = await Directory.systemTemp.createTemp('younz-context-safe-');
      addTearDown(() => root.delete(recursive: true));
      await File(
        '${root.path}${Platform.pathSeparator}ordinary.dart',
      ).writeAsString('class OrdinaryWorkspaceSource {}\n');
      final engine = ContextEngine(root.path);

      final selection = await engine.select('OrdinaryWorkspaceSource');

      expect(selection.files, isEmpty);
      expect(selection.promptContext, isEmpty);
    },
  );

  test(
    'ContextEngine tidak membaca file baru dari perubahan eksternal',
    () async {
      final root = await Directory.systemTemp.createTemp('younz-context-');
      addTearDown(() => root.delete(recursive: true));
      await File(
        '${root.path}${Platform.pathSeparator}initial.dart',
      ).writeAsString('class InitialFile {}\n');
      final intelligence = CodeIntelligenceService(root.path);
      final engine = ContextEngine(root.path, intelligence: intelligence);
      await intelligence.ensureIndexed();
      await File(
        '${root.path}${Platform.pathSeparator}external_change.dart',
      ).writeAsString('class ExternalChangeDetector {}\n');

      final selection = await engine.select('ExternalChangeDetector');

      expect(selection.files, isEmpty);
      expect(selection.promptContext, isEmpty);
    },
  );

  test('ContextEngine tidak membaca file relevan otomatis', () async {
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

    expect(selection.files, isEmpty);
    expect(selection.totalCharacters, lessThanOrEqualTo(220));
    expect(selection.promptContext, isEmpty);
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

  test(
    'ContextEngine tidak membaca kandidat meski attachment dikecualikan',
    () async {
      final root = await Directory.systemTemp.createTemp('younz-context-');
      addTearDown(() => root.delete(recursive: true));
      await File(
        '${root.path}${Platform.pathSeparator}dominant.dart',
      ).writeAsString(List.filled(260, 'void authTokenLogin() {}').join('\n'));
      await File(
        '${root.path}${Platform.pathSeparator}secondary.dart',
      ).writeAsString('class AuthTokenStore {}\n');
      final engine = ContextEngine(root.path);

      final diverse = await engine.select(
        'auth token login',
        maxFiles: 8,
        excludedPaths: const {'./folder/../dominant.dart'},
      );

      expect(diverse.files, isEmpty);
      expect(diverse.promptContext, isEmpty);
    },
  );

  test(
    'ContextEngine menolak database URL dengan embedded credential',
    () async {
      final root = await Directory.systemTemp.createTemp('context-db-url-');
      addTearDown(() => root.delete(recursive: true));
      final file = File('${root.path}${Platform.pathSeparator}database.dart');
      final password = ['x'].join();
      await file.writeAsString(
        "const databaseUrl = 'postgresql://app_user:$password@db.internal/app';",
      );
      final engine = ContextEngine(root.path);

      final selected = await engine.select('database connection');

      expect(selected.files, isEmpty);
      expect(selected.promptContext, isNot(contains(password)));
    },
  );

  test(
    'ContextEngine menolak URI dengan delimiter userinfo ter-encode',
    () async {
      final root = await Directory.systemTemp.createTemp('context-db-url-');
      addTearDown(() => root.delete(recursive: true));
      final encodedUserInfo = ['user', '%3A', 'x'].join();
      final uri = 'postgresql://$encodedUserInfo@db.internal/app';
      await File(
        '${root.path}${Platform.pathSeparator}database.dart',
      ).writeAsString("const databaseUrl = '$uri';");
      final engine = ContextEngine(root.path);

      final selected = await engine.select('database connection');

      expect(selected.files, isEmpty);
      expect(selected.promptContext, isNot(contains(encodedUserInfo)));
    },
  );

  test('ContextEngine menolak file credential umum seluruhnya', () async {
    final root = await Directory.systemTemp.createTemp('younz-context-');
    addTearDown(() => root.delete(recursive: true));
    await File(
      '${root.path}${Platform.pathSeparator}credentials.json',
    ).writeAsString(
      '{"client_email":"service@example.com","private_key":"hidden-value"}',
    );
    await File(
      '${root.path}${Platform.pathSeparator}secrets.yaml',
    ).writeAsString('login_token: hidden-token-value\n');
    final engine = ContextEngine(root.path);

    final selection = await engine.select('credentials secret login token');

    expect(selection.files, isEmpty);
    expect(selection.promptContext, isNot(contains('hidden')));
  });

  test(
    'ContextEngine membuang isi bila target berubah saat boundary read',
    () async {
      final root = await Directory.systemTemp.createTemp('younz-context-race-');
      final outside = await Directory.systemTemp.createTemp(
        'younz-outside-race-',
      );
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
        if (await outside.exists()) await outside.delete(recursive: true);
      });
      final indexed = File('${root.path}${Platform.pathSeparator}race.dart');
      await indexed.writeAsString('class RaceTarget {}\n');
      final external = File(
        '${outside.path}${Platform.pathSeparator}race.dart',
      );
      await external.writeAsString(
        'class RaceTarget { String hidden = "leak"; }\n',
      );
      final intelligence = CodeIntelligenceService(root.path);
      await intelligence.ensureIndexed();
      var swapped = false;
      final engine = ContextEngine(
        root.path,
        intelligence: intelligence,
        beforeRead: (path) async {
          if (swapped) return;
          swapped = true;
          await File(path).delete();
          await Link(path).create(external.path);
        },
      );

      final selection = await engine.select('RaceTarget');

      expect(selection.files, isEmpty);
      expect(selection.promptContext, isNot(contains('leak')));
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
