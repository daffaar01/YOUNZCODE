import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kode_agent_desktop/main.dart';
import 'package:kode_agent_desktop/lottie_support.dart';
import 'package:kode_agent_desktop/models/chat_entry.dart';
import 'package:kode_agent_desktop/models/chat_session.dart';
import 'package:kode_agent_desktop/models/agent_goal.dart';
import 'package:kode_agent_desktop/services/chat_session_store.dart';
import 'package:lottie/lottie.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pumpLoaded(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  await tester.pump();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  await tester.pump(const Duration(milliseconds: 300));
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int attempts = 20,
}) async {
  for (var attempt = 0; attempt < attempts; attempt++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void _setMockPreferences(Map<String, Object> values) {
  SharedPreferences.setMockInitialValues({
    'onboarding_complete': true,
    ...values,
  });
}

void main() {
  testWidgets('aset loader Lottie dapat didekode', (tester) async {
    final assetData = await rootBundle.load(
      'assets/younzcode_cat_loading.lottie',
    );
    final composition = await decodeDotLottie(
      assetData.buffer.asUint8List(
        assetData.offsetInBytes,
        assetData.lengthInBytes,
      ),
    );

    expect(composition, isNotNull);
    expect(composition!.bounds.width, 280);
    expect(composition.bounds.height, 200);
    expect(composition.layers, hasLength(11));

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: RepaintBoundary(
            key: const ValueKey('test-lottie-loader'),
            child: SizedBox(
              width: 280,
              height: 200,
              child: Lottie.asset(
                'assets/younzcode_cat_loading.lottie',
                decoder: decodeDotLottie,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byKey(const ValueKey('test-lottie-loader')), findsOneWidget);
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('test-lottie-loader')),
    );
    final pixels = await tester.runAsync(() async {
      final renderedImage = await boundary.toImage();
      final byteData = await renderedImage.toByteData();
      renderedImage.dispose();
      return byteData!.buffer.asUint8List();
    });
    final renderedPixels = pixels!;
    var paintedPixels = 0;
    for (
      var alphaIndex = 3;
      alphaIndex < renderedPixels.length;
      alphaIndex += 4
    ) {
      if (renderedPixels[alphaIndex] > 0) paintedPixels++;
    }
    expect(paintedPixels, greaterThan(100));
    expect(tester.takeException(), isNull);
  });

  testWidgets('menampilkan layar utama agent', (tester) async {
    _setMockPreferences({});
    await tester.binding.setSurfaceSize(const Size(1400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KodeAgentApp());
    await _pumpLoaded(tester);

    expect(find.text('YOUNZCODE'), findsOneWidget);
    expect(find.byKey(const ValueKey('classic-sidebar')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('classic-codex-workspace-layout')),
      findsOneWidget,
    );
    expect(find.textContaining('Environment: Windows'), findsNothing);
    expect(find.text('AGENT SESSION'), findsNothing);
    expect(find.text('YOUNZCODE DESKTOP'), findsNothing);
    expect(find.byKey(const ValueKey('model-selector')), findsOneWidget);
    expect(find.text('MANAGE MODELS'), findsOneWidget);
    expect(find.byKey(const ValueKey('composer-shortcuts')), findsOneWidget);
    expect(find.text('Ctrl+K'), findsOneWidget);
    expect(find.text('/review'), findsOneWidget);
    expect(find.text('PROJECT'), findsOneWidget);
    expect(find.text('What are we building?'), findsOneWidget);
    expect(
      find.text('Explain Codebase').evaluate().isNotEmpty ||
          find.text('EXPLAIN').evaluate().isNotEmpty,
      isTrue,
    );
    expect(find.text('RECOMMENDED'), findsOneWidget);
    expect(find.text('Ctrl+Enter'), findsOneWidget);
    expect(find.byKey(const ValueKey('workspace-setup-card')), findsOneWidget);
    expect(find.text('SETUP WORKSPACE'), findsOneWidget);
    expect(find.text('0/3 SIAP'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('empty-choose-workspace')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('classic-environment-panel')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('environment-setup-banner')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('environment-setup-action')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('environment-add-source')), findsNothing);
  });

  testWidgets('empty state tidak menumpuk pada jendela pendek', (tester) async {
    _setMockPreferences({});
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KodeAgentApp());
    await _pumpLoaded(tester);

    final setupRect = tester.getRect(
      find.byKey(const ValueKey('workspace-setup-card')),
    );
    final quickStartRect = tester.getRect(
      find.byKey(const ValueKey('quick-start-compact')),
    );
    final composerRect = tester.getRect(
      find.byKey(const ValueKey('composer-shell')),
    );

    expect(find.byKey(const ValueKey('quick-start-compact')), findsOneWidget);
    expect(composerRect.top, greaterThanOrEqualTo(setupRect.bottom));
    expect(composerRect.top, greaterThanOrEqualTo(quickStartRect.bottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets('dashboard workspace aktif menampilkan ringkasan proyek', (
    tester,
  ) async {
    final workspace = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('younzcode-dashboard-'),
    ))!;
    addTearDown(() => tester.runAsync(() => workspace.delete(recursive: true)));
    _setMockPreferences({'workspace': workspace.path});
    await tester.binding.setSurfaceSize(const Size(1400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KodeAgentApp());
    await _pumpLoaded(tester);

    expect(find.byKey(const ValueKey('workspace-dashboard')), findsOneWidget);
    expect(find.text('PERUBAHAN GIT'), findsOneWidget);
    expect(find.text('QUALITY GATE'), findsOneWidget);
    expect(find.text('TASK AGENT'), findsOneWidget);
    expect(find.byKey(const ValueKey('dashboard-open-git')), findsOneWidget);
    expect(find.text('TULIS TASK'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('preset Focus mengubah layout dan kepadatan workspace', (
    tester,
  ) async {
    _setMockPreferences({'workspace_layout': 'focus'});
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KodeAgentApp());
    await _pumpLoaded(tester);

    await tester.tap(find.byKey(const ValueKey('rail-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('APPEARANCE'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('appearance-preset')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('FOCUS').last);
    await tester.pump();
    await tester.tap(find.text('SAVE SETTINGS'));
    await tester.pumpAndSettle();

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('ui_preset'), 'focus');
    expect(preferences.getString('workspace_layout'), 'focus');
    expect(preferences.getString('composer_density'), 'compact');
    expect(
      find.byKey(const ValueKey('focus-workspace-layout')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('onboarding memiliki progress dan navigasi tiga langkah', (
    tester,
  ) async {
    final workspace = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('younzcode-onboarding-'),
    ))!;
    addTearDown(() => tester.runAsync(() => workspace.delete(recursive: true)));
    SharedPreferences.setMockInitialValues({
      'workspace': workspace.path,
      'onboarding_complete': false,
    });
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KodeAgentApp());
    await _pumpLoaded(tester);
    await _pumpUntilFound(
      tester,
      find.byKey(const ValueKey('onboarding-dialog')),
    );

    expect(find.byKey(const ValueKey('onboarding-dialog')), findsOneWidget);
    expect(find.byKey(const ValueKey('onboarding-progress')), findsOneWidget);
    expect(find.byKey(const ValueKey('onboarding-step-0')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('onboarding-next')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('onboarding-step-1')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('onboarding-back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('onboarding-step-0')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('onboarding-skip')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('onboarding-dialog')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('workspace picker menampilkan pencarian dan workspace terakhir', (
    tester,
  ) async {
    final createdRoot = await tester.runAsync(
      () => Directory.systemTemp.createTemp('younzcode-picker-'),
    );
    expect(createdRoot, isNotNull);
    final root = createdRoot as Directory;
    final alpha = Directory('${root.path}${Platform.pathSeparator}alpha-app');
    final beta = Directory('${root.path}${Platform.pathSeparator}beta-app');
    await tester.runAsync(() async {
      await alpha.create();
      await beta.create();
    });
    addTearDown(() => tester.runAsync(() => root.delete(recursive: true)));
    _setMockPreferences({
      'recent_workspaces': [alpha.path, beta.path],
    });
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KodeAgentApp());
    await _pumpLoaded(tester);

    final chooseWorkspace = find.byKey(
      const ValueKey('empty-choose-workspace'),
    );
    await tester.ensureVisible(chooseWorkspace);
    await tester.tap(chooseWorkspace);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    await tester.pumpAndSettle();

    final picker = find.byKey(const ValueKey('workspace-picker-dialog'));
    expect(picker, findsOneWidget);
    expect(
      find.byKey(const ValueKey('workspace-picker-search')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: picker, matching: find.text('alpha-app')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: picker, matching: find.text('beta-app')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('workspace-picker-browse')),
      findsOneWidget,
    );
    expect(find.byTooltip('Pin workspace'), findsWidgets);
    await tester.tap(find.byTooltip('Pin workspace').first);
    await tester.pump();
    expect(find.byTooltip('Unpin workspace'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('workspace-picker-search')),
      'beta',
    );
    await tester.pump();
    expect(
      find.descendant(of: picker, matching: find.text('beta-app')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: picker, matching: find.text('alpha-app')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('shortcut composer menyiapkan command untuk ditinjau', (
    tester,
  ) async {
    _setMockPreferences({});
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KodeAgentApp());
    await _pumpLoaded(tester);

    await tester.tap(find.text('/review'));
    await tester.pump();

    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('prompt-field')),
    );
    expect(field.controller!.text, '/review');
    expect(tester.takeException(), isNull);
  });

  testWidgets('composer menyediakan template dan paste code', (tester) async {
    _setMockPreferences({});
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KodeAgentApp());
    await _pumpLoaded(tester);

    await tester.tap(find.byKey(const ValueKey('composer-templates')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('prompt-templates-dialog')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('prompt-template-Fix Bug')));
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('prompt-field')))
          .controller!
          .text,
      contains('Investigasi bug'),
    );

    expect(find.byKey(const ValueKey('composer-history')), findsOneWidget);
    expect(find.byKey(const ValueKey('composer-paste-code')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tools composer otomatis ringkas pada jendela pendek', (
    tester,
  ) async {
    _setMockPreferences({});
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KodeAgentApp());
    await _pumpLoaded(tester);

    expect(find.byKey(const ValueKey('composer-tools-toggle')), findsOneWidget);
    expect(find.byKey(const ValueKey('classic-add-context')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('composer-tools-toggle')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('classic-add-context')), findsOneWidget);
    expect(find.byKey(const ValueKey('classic-plugins')), findsOneWidget);
    expect(find.byKey(const ValueKey('classic-subagent')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('kepadatan composer dapat diubah dan disimpan', (tester) async {
    _setMockPreferences({'composer_density': 'comfortable'});
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KodeAgentApp());
    await _pumpLoaded(tester);

    var field = tester.widget<TextField>(
      find.byKey(const ValueKey('prompt-field')),
    );
    expect(field.maxLines, 5);

    await tester.tap(find.byKey(const ValueKey('composer-density-toggle')));
    await tester.pumpAndSettle();

    field = tester.widget<TextField>(
      find.byKey(const ValueKey('prompt-field')),
    );
    expect(field.maxLines, 3);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('composer_density'), 'compact');
    expect(tester.takeException(), isNull);
  });

  testWidgets('membuka playground Image Generation dari command rail', (
    tester,
  ) async {
    _setMockPreferences({
      'workspace_layout': 'focus',
      'base_url': 'http://localhost:20128',
      'model': 'cx/gpt-5.5-image',
      'models': ['cx/gpt-5.5-image'],
    });
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KodeAgentApp());
    await _pumpLoaded(tester);

    await tester.tap(find.byKey(const ValueKey('rail-images')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('image-generation-view')), findsOneWidget);
    expect(find.text('IMAGE GENERATION'), findsOneWidget);
    expect(
      find.text('http://127.0.0.1:20128/v1/images/generations'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('image-run')), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('image-prompt')),
      'A cute cat wearing a hat',
    );
    await tester.pump();
    final runButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey('image-run')),
    );
    expect(runButton.onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing persisted workspace does not leave startup loading', (
    tester,
  ) async {
    _setMockPreferences({
      'workspace':
          '${Directory.systemTemp.path}${Platform.pathSeparator}'
          'missing-younzcode-workspace',
    });
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KodeAgentApp());
    await _pumpLoaded(tester);

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byKey(const ValueKey('prompt-field')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('membuka project settings lengkap', (tester) async {
    _setMockPreferences({'workspace_layout': 'focus'});
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KodeAgentApp());
    await _pumpLoaded(tester);

    await tester.tap(find.byKey(const ValueKey('rail-settings')));
    await tester.pumpAndSettle();

    expect(find.text('PROJECT SETTINGS'), findsOneWidget);
    expect(find.text('GENERAL'), findsWidgets);
    expect(find.text('APPEARANCE'), findsOneWidget);
    expect(find.text('ENV VARIABLES'), findsOneWidget);
    expect(find.text('PERMISSIONS'), findsOneWidget);
    expect(find.text('SECURITY'), findsOneWidget);
    expect(find.text('API'), findsOneWidget);

    await tester.tap(find.text('API'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('provider-status-card')), findsOneWidget);
  });

  testWidgets('appearance tersimpan dan model favorit diprioritaskan', (
    tester,
  ) async {
    _setMockPreferences({
      'workspace_layout': 'focus',
      'model': 'model-a',
      'models': ['model-a', 'model-b'],
    });
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KodeAgentApp());
    await _pumpLoaded(tester);

    await tester.tap(find.byKey(const ValueKey('rail-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('APPEARANCE'));
    await tester.pumpAndSettle();

    final slider = tester.widget<Slider>(
      find.byKey(const ValueKey('appearance-font-scale')),
    );
    slider.onChanged!(1.2);
    await tester.pump();
    await tester.tap(find.text('COMPACT'));
    await tester.pump();

    const accent = Color(0xFF2F9E69);
    await tester.tap(
      find.byKey(ValueKey('appearance-accent-${accent.toARGB32()}')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('appearance-favorite-model')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('model-b').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('SAVE SETTINGS'));
    await tester.pumpAndSettle();

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getDouble('font_scale'), 1.2);
    expect(preferences.getString('ui_density'), 'compact');
    expect(preferences.getInt('accent_color'), accent.toARGB32());
    expect(preferences.getString('favorite_model'), 'model-b');

    final selector = tester.widget<DropdownButton<String>>(
      find.byKey(const ValueKey('model-selector')),
    );
    expect(selector.items!.first.value, 'model-b');
    expect(tester.takeException(), isNull);
  });

  testWidgets('toggle UPDATE TELEMETRY di Project Settings tersimpan', (
    tester,
  ) async {
    _setMockPreferences({'workspace_layout': 'focus'});
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KodeAgentApp());
    await _pumpLoaded(tester);

    // Buka Project Settings dan masuk ke tab PERMISSIONS.
    await tester.tap(find.byKey(const ValueKey('rail-settings')));
    await tester.pumpAndSettle();
    expect(find.text('PROJECT SETTINGS'), findsOneWidget);
    await tester.tap(find.text('PERMISSIONS'));
    await tester.pumpAndSettle();

    // Temukan Switch di baris UPDATE TELEMETRY.
    final telemetryRow = find.ancestor(
      of: find.text('UPDATE TELEMETRY'),
      matching: find.byType(Row),
    );
    final telemetrySwitch = find.descendant(
      of: telemetryRow,
      matching: find.byType(Switch),
    );
    expect(telemetrySwitch, findsOneWidget);
    // Default: telemetri aktif.
    expect(tester.widget<Switch>(telemetrySwitch).value, isTrue);

    // Matikan telemetri, lalu simpan.
    await tester.ensureVisible(telemetrySwitch);
    await tester.tap(telemetrySwitch);
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(telemetrySwitch).value, isFalse);
    await tester.tap(find.text('SAVE SETTINGS'));
    await tester.pumpAndSettle();
    expect(find.text('PROJECT SETTINGS'), findsNothing);

    // Nilai tersimpan di SharedPreferences.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('update_ping_enabled'), isFalse);

    // Buka lagi: toggle menampilkan nilai yang tersimpan.
    await tester.tap(find.byKey(const ValueKey('rail-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PERMISSIONS'));
    await tester.pumpAndSettle();
    final reopenedSwitch = find.descendant(
      of: find.ancestor(
        of: find.text('UPDATE TELEMETRY'),
        matching: find.byType(Row),
      ),
      matching: find.byType(Switch),
    );
    expect(tester.widget<Switch>(reopenedSwitch).value, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Enter mengirim dan Shift+Enter membuat baris baru', (
    tester,
  ) async {
    _setMockPreferences({'workspace_layout': 'focus'});
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KodeAgentApp());
    await _pumpLoaded(tester);

    final field = find.byKey(const ValueKey('prompt-field'));
    await tester.tap(field);
    await tester.enterText(field, 'baris pertama');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.enterText(field, 'baris pertama\nbaris kedua');

    final input = tester.widget<TextField>(field);
    expect(input.controller!.text, 'baris pertama\nbaris kedua');
    expect(
      find.text('Pilih folder workspace yang valid terlebih dahulu.'),
      findsNothing,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(
      find.text('Pilih folder workspace yang valid terlebih dahulu.'),
      findsOneWidget,
    );
  });

  testWidgets('tombol kirim berada di dalam area prompt', (tester) async {
    _setMockPreferences({});
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KodeAgentApp());
    await _pumpLoaded(tester);

    final promptRect = tester.getRect(
      find.byKey(const ValueKey('prompt-field')),
    );
    final sendRect = tester.getRect(find.byKey(const ValueKey('send-agent')));
    final shell = tester.widget<Container>(
      find.byKey(const ValueKey('composer-shell')),
    );
    final shellDecoration = shell.decoration! as BoxDecoration;

    expect(promptRect.width, lessThanOrEqualTo(860.5));
    expect(promptRect.contains(sendRect.center), isTrue);
    expect(sendRect.height, closeTo(38, 0.5));
    expect(shellDecoration.border, isNotNull);
    expect((shellDecoration.border! as Border).top.width, 1);
    expect(shellDecoration.borderRadius, BorderRadius.circular(12));
    expect(
      find.text(
        'Enter kirim · Shift+Enter baris baru · Drop file untuk context',
      ),
      findsOneWidget,
    );
  });

  testWidgets('slash command menu menampilkan bantuan lokal', (tester) async {
    _setMockPreferences({});
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KodeAgentApp());
    await _pumpLoaded(tester);

    final field = find.byKey(const ValueKey('prompt-field'));
    await tester.enterText(field, '/');
    await tester.pump();
    expect(find.byKey(const ValueKey('slash-command-menu')), findsOneWidget);
    for (final command in const [
      '/graphify',
      '/mcp',
      '/review',
      '/fork',
      '/model',
      '/share',
      '/open',
      '/skill',
    ]) {
      if (command == '/review') {
        expect(
          find.byKey(const ValueKey('slash-command-review')),
          findsOneWidget,
        );
      } else {
        expect(find.text(command), findsOneWidget);
      }
    }
    expect(find.text('/help'), findsOneWidget);
    expect(find.text('/terminal'), findsOneWidget);

    final helpCommand = find.byKey(const ValueKey('slash-command-help'));
    await tester.ensureVisible(helpCommand);
    await tester.pumpAndSettle();
    await tester.tap(helpCommand);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Slash commands:'), findsOneWidget);
    expect(
      find.text('Pilih folder workspace yang valid terlebih dahulu.'),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('slash command review dan fork berfungsi lokal', (tester) async {
    final workspace = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('younzcode-command-'),
    ))!;
    addTearDown(() => tester.runAsync(() => workspace.delete(recursive: true)));
    _setMockPreferences({'workspace': workspace.path});
    await ChatSessionStore().save([
      ChatSession(
        id: 'command-chat',
        workspace: workspace.path,
        updatedAt: DateTime(2026, 7, 25),
        entries: const [ChatEntry(role: ChatRole.user, content: 'Pesan awal')],
      ),
    ]);
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KodeAgentApp());
    await _pumpLoaded(tester);

    final field = find.byKey(const ValueKey('prompt-field'));
    await tester.tap(field);
    await tester.enterText(field, '/review');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Tidak ada perubahan agent'), findsOneWidget);

    await tester.enterText(field, '/fork');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Chat di-fork'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('slash command model dan skill membuka manager, mcp masuk chat', (
    tester,
  ) async {
    _setMockPreferences({});
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KodeAgentApp());
    await _pumpLoaded(tester);
    final field = find.byKey(const ValueKey('prompt-field'));

    await tester.tap(field);
    await tester.enterText(field, '/model');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('MODEL CONNECTION'), findsOneWidget);
    await tester.tap(find.byTooltip('Tutup'));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(field);
    await tester.enterText(field, '/mcp');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.textContaining('Belum ada MCP server yang diimpor'),
      findsOneWidget,
    );
    expect(find.text('ADD-ON MANAGER'), findsNothing);

    await tester.tap(field);
    await tester.enterText(field, '/skill');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('ADD-ON MANAGER'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('slash command share menyalin percakapan', (tester) async {
    final workspace = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('younzcode-command-share-'),
    ))!;
    addTearDown(() => tester.runAsync(() => workspace.delete(recursive: true)));
    _setMockPreferences({'workspace': workspace.path});
    await ChatSessionStore().save([
      ChatSession(
        id: 'share-chat',
        workspace: workspace.path,
        updatedAt: DateTime(2026, 7, 25),
        entries: const [ChatEntry(role: ChatRole.user, content: 'Bagikan ini')],
      ),
    ]);
    String? copiedText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KodeAgentApp());
    await _pumpLoaded(tester);
    final field = find.byKey(const ValueKey('prompt-field'));

    await tester.tap(field);
    await tester.enterText(field, '/share');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(copiedText, contains('Bagikan ini'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('slash command graphify memvalidasi workspace', (tester) async {
    _setMockPreferences({});
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KodeAgentApp());
    await _pumpLoaded(tester);
    final field = find.byKey(const ValueKey('prompt-field'));

    await tester.tap(field);
    await tester.enterText(field, '/graphify');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(
      find.text('Pilih workspace sebelum menjalankan Graphify.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('slash command plan dieksekusi tanpa dikirim ke model', (
    tester,
  ) async {
    _setMockPreferences({});
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KodeAgentApp());
    await _pumpLoaded(tester);

    final field = find.byKey(const ValueKey('prompt-field'));
    await tester.tap(field);
    await tester.enterText(field, '/plan');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(find.textContaining('READ-ONLY'), findsOneWidget);
    expect(
      find.text('Pilih folder workspace yang valid terlebih dahulu.'),
      findsNothing,
    );
    expect(tester.widget<TextField>(field).controller?.text, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('slash command goal tanpa objective menampilkan bantuan', (
    tester,
  ) async {
    _setMockPreferences({});
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KodeAgentApp());
    await _pumpLoaded(tester);

    final field = find.byKey(const ValueKey('prompt-field'));
    await tester.tap(field);
    await tester.enterText(field, '/goal');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(
      find.textContaining(
        'Belum ada goal. Gunakan "/goal tujuan yang ingin diselesaikan".',
      ),
      findsOneWidget,
    );
    expect(tester.widget<TextField>(field).controller?.text, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'goal tersimpan dipulihkan sebagai banner yang dapat dilanjutkan',
    (tester) async {
      final workspace = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('younzcode-goal-'),
      ))!;
      addTearDown(
        () => tester.runAsync(() => workspace.delete(recursive: true)),
      );
      _setMockPreferences({'workspace': workspace.path});
      await ChatSessionStore().save([
        ChatSession(
          id: 'goal-session',
          workspace: workspace.path,
          updatedAt: DateTime(2026, 7, 29),
          entries: const [
            ChatEntry(
              role: ChatRole.user,
              content: '/goal selesaikan aplikasi',
            ),
          ],
          goal: AgentGoal(
            objective: 'Selesaikan aplikasi sampai seluruh test lulus',
            status: AgentGoalStatus.paused,
            turnCount: 2,
            updatedAt: DateTime(2026, 7, 29),
          ),
        ),
      ]);
      await tester.binding.setSurfaceSize(const Size(1400, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const KodeAgentApp());
      await _pumpLoaded(tester);

      expect(find.byKey(const ValueKey('goal-banner')), findsOneWidget);
      expect(find.text('GOAL PAUSED · 2 TURN'), findsOneWidget);
      expect(
        find.text('Selesaikan aplikasi sampai seluruh test lulus'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('goal-resume')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test('workspace tree memiliki folder dan file yang dapat dibaca', () async {
    final workspace = await Directory.systemTemp.createTemp('younzcode-tree-');
    await Directory('${workspace.path}${Platform.pathSeparator}lib').create();
    await File(
      '${workspace.path}${Platform.pathSeparator}README.md',
    ).writeAsString('# Project');
    await File(
      '${workspace.path}${Platform.pathSeparator}lib${Platform.pathSeparator}main.dart',
    ).writeAsString('void main() {}');
    addTearDown(() => workspace.delete(recursive: true));

    final rootEntries = await Directory(workspace.path).list().toList();
    final libEntries = await Directory(
      '${workspace.path}${Platform.pathSeparator}lib',
    ).list().toList();
    expect(
      rootEntries.any((entry) => entry.path.endsWith('README.md')),
      isTrue,
    );
    expect(rootEntries.any((entry) => entry.path.endsWith('lib')), isTrue);
    expect(libEntries.single.path.endsWith('main.dart'), isTrue);
  });

  testWidgets('model manager dapat menambahkan model baru', (tester) async {
    _setMockPreferences({});
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KodeAgentApp());
    await _pumpLoaded(tester);
    expect(tester.takeException(), isNull, reason: 'main layout');

    await tester.tap(find.text('MANAGE MODELS'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull, reason: 'model dialog');
    expect(find.text('MODEL CONNECTION'), findsOneWidget);
    expect(find.text('gpt-4.1-mini'), findsWidgets);

    await tester.enterText(
      find.widgetWithText(TextField, 'Model ID, contoh gpt-4.1'),
      'gpt-4.1',
    );
    final addModel = find.text('ADD MODEL');
    await tester.ensureVisible(addModel);
    await tester.pumpAndSettle();
    await tester.tap(addModel);
    await tester.pump();
    expect(find.text('gpt-4.1'), findsOneWidget);
  });

  testWidgets('model manager tetap rapi pada viewport sempit', (tester) async {
    _setMockPreferences({});
    await tester.binding.setSurfaceSize(const Size(565, 980));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KodeAgentApp());
    await _pumpLoaded(tester);
    tester.takeException();

    await tester.tap(find.byKey(const ValueKey('manage-models-compact')));
    await tester.pumpAndSettle();

    expect(find.text('MODEL CONNECTION'), findsOneWidget);
    expect(find.text('CHECK FOR UPDATES'), findsOneWidget);
    expect(find.text('SAVE MODELS'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('preset provider mengisi Base URL dan model contoh', (
    tester,
  ) async {
    _setMockPreferences({});
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KodeAgentApp());
    await _pumpLoaded(tester);

    await tester.tap(find.text('MANAGE MODELS'));
    await tester.pumpAndSettle();
    expect(find.text('MODEL CONNECTION'), findsOneWidget);
    expect(find.byKey(const ValueKey('provider-preset')), findsOneWidget);
    expect(find.byKey(const ValueKey('fetch-models-button')), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('model-api-key-field'))).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const ValueKey('fetch-models-button'))).dy,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('provider-preset')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('provider-search-field')),
      'Google Gemini (OpenAI-compatible)',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey('provider-option-Google Gemini (OpenAI-compatible)'),
      ),
    );
    await tester.pumpAndSettle();

    // Base URL auto-filled and example models loaded.
    expect(
      find.text('https://generativelanguage.googleapis.com/v1beta/openai'),
      findsOneWidget,
    );
    expect(find.text('gemini-2.5-pro'), findsWidgets);
  });

  testWidgets('model manager menyediakan katalog provider AI utama', (
    tester,
  ) async {
    _setMockPreferences({});
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KodeAgentApp());
    await _pumpLoaded(tester);

    await tester.tap(find.text('MANAGE MODELS'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('provider-preset')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('provider-search-field')), findsOneWidget);
    final searchField = find.byKey(const ValueKey('provider-search-field'));

    for (final provider in const [
      'OpenAI',
      'Anthropic Claude (native)',
      'Google Gemini (native)',
      'OpenRouter (Claude, Gemini, dll)',
      'DeepSeek',
      'Mistral AI',
      'Cohere',
      'Together AI',
      'Fireworks AI',
      'Cerebras',
      'SambaNova Cloud',
      'xAI Grok',
      'Perplexity',
      'Moonshot AI (Kimi)',
      'Zhipu AI (GLM)',
      'SiliconFlow',
      'Hugging Face Inference',
      'NVIDIA NIM',
      'Groq',
      'AgentRouter (OpenAI-compatible)',
      '9router (lokal)',
      'Ollama (lokal)',
    ]) {
      await tester.enterText(searchField, provider);
      await tester.pump();
      expect(
        find.byKey(ValueKey('provider-option-$provider')),
        findsOneWidget,
        reason: provider,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('pencarian provider memfilter katalog dan memilih hasil', (
    tester,
  ) async {
    _setMockPreferences({});
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KodeAgentApp());
    await _pumpLoaded(tester);

    await tester.tap(find.text('MANAGE MODELS'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('provider-preset')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('provider-search-field')),
      'cerebras',
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('provider-option-Cerebras')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('provider-option-OpenAI')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('provider-option-Cerebras')));
    await tester.pumpAndSettle();
    expect(find.text('Cerebras'), findsOneWidget);
    expect(find.text('https://api.cerebras.ai/v1'), findsOneWidget);
  });

  testWidgets('preset Anthropic native mengisi Base URL dan model native', (
    tester,
  ) async {
    _setMockPreferences({});
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KodeAgentApp());
    await _pumpLoaded(tester);

    await tester.tap(find.text('MANAGE MODELS'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('provider-preset')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('provider-search-field')),
      'Anthropic Claude (native)',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('provider-option-Anthropic Claude (native)')),
    );
    await tester.pumpAndSettle();

    expect(find.text('https://api.anthropic.com'), findsOneWidget);
    expect(find.text('claude-opus-4-8'), findsWidgets);
  });

  testWidgets('preset AgentRouter memakai endpoint milik akun pengguna', (
    tester,
  ) async {
    _setMockPreferences({});
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KodeAgentApp());
    await _pumpLoaded(tester);

    await tester.tap(find.text('MANAGE MODELS'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('provider-preset')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('provider-search-field')),
      'AgentRouter',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey('provider-option-AgentRouter (OpenAI-compatible)'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('https://agentrouter.org/v1'), findsOneWidget);
    expect(find.text('gpt-5.5'), findsWidgets);
  });

  testWidgets(
    'fetch provider internet tanpa API key dihentikan sebelum request',
    (tester) async {
      _setMockPreferences({});
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const KodeAgentApp());
      await _pumpLoaded(tester);

      await _pumpUntilFound(tester, find.text('MANAGE MODELS'));
      await tester.tap(find.text('MANAGE MODELS'));
      await tester.pumpAndSettle();
      final fetchButton = find.byKey(const ValueKey('fetch-models-button'));
      await tester.ensureVisible(fetchButton);
      await tester.tap(fetchButton);
      await tester.pump();

      expect(
        find.textContaining('Isi API KEY terlebih dahulu'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'preset 9router mengisi Base URL loopback tanpa menghapus model',
    (tester) async {
      _setMockPreferences({});
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const KodeAgentApp());
      await _pumpLoaded(tester);

      await _pumpUntilFound(tester, find.text('MANAGE MODELS'));
      await tester.tap(find.text('MANAGE MODELS'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('provider-preset')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('provider-search-field')),
        '9router',
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('provider-option-9router (lokal)')),
      );
      await tester.pumpAndSettle();

      expect(find.text('http://127.0.0.1:20128/v1'), findsWidgets);
      // Preset with no example models keeps the existing model list.
      expect(find.text('gpt-4.1-mini'), findsWidgets);
    },
  );

  testWidgets('Cancel menutup model manager tanpa error', (tester) async {
    _setMockPreferences({});
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KodeAgentApp());
    await _pumpLoaded(tester);

    await tester.tap(find.text('MANAGE MODELS'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CANCEL'));
    await tester.pumpAndSettle();

    expect(find.text('MODEL CONNECTION'), findsNothing);
    expect(find.text('YOUNZCODE'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('X menutup model manager tanpa black screen', (tester) async {
    _setMockPreferences({});
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KodeAgentApp());
    await _pumpLoaded(tester);

    await tester.tap(find.text('MANAGE MODELS'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Tutup'));
    await tester.pumpAndSettle();

    expect(find.text('MODEL CONNECTION'), findsNothing);
    expect(find.text('YOUNZCODE'), findsOneWidget);
    final layoutError = tester.takeException();
    if (layoutError != null) throw layoutError;
  });

  testWidgets('model manager dapat discroll pada jendela pendek', (
    tester,
  ) async {
    _setMockPreferences({});
    await tester.binding.setSurfaceSize(const Size(900, 480));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KodeAgentApp());
    await _pumpLoaded(tester);

    await tester.tap(find.text('MANAGE MODELS'));
    await tester.pumpAndSettle();

    expect(find.text('MODEL CONNECTION'), findsOneWidget);
    expect(find.text('SAVE MODELS'), findsOneWidget);
    final dialogScroll = find.byKey(const ValueKey('model-dialog-scroll'));
    expect(dialogScroll, findsOneWidget);
    await tester.drag(dialogScroll, const Offset(0, -180));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'model dialog scroll');
    expect(find.byKey(const ValueKey('model-api-key-field')), findsOneWidget);
    expect(find.text('API KEY'), findsOneWidget);
  });

  testWidgets('model manager mengikuti tinggi konten pada jendela tinggi', (
    tester,
  ) async {
    _setMockPreferences({});
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KodeAgentApp());
    await _pumpLoaded(tester);

    await tester.tap(find.text('MANAGE MODELS'));
    await tester.pumpAndSettle();

    final panel = find.byKey(const ValueKey('model-dialog-panel'));
    expect(panel, findsOneWidget);
    expect(tester.getSize(panel).height, lessThan(800));
    expect(tester.takeException(), isNull);
  });

  testWidgets('workspace menyediakan mode Classic dan Focus', (tester) async {
    _setMockPreferences({});
    await tester.binding.setSurfaceSize(const Size(1500, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KodeAgentApp());
    await _pumpLoaded(tester);

    expect(find.byKey(const ValueKey('focus-workspace-layout')), findsNothing);
    expect(
      find.byKey(const ValueKey('classic-codex-workspace-layout')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('classic-environment-panel')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('workspace-layout-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Focus'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('focus-workspace-layout')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('focus-agent-panel')), findsOneWidget);
    expect(find.byKey(const ValueKey('workspace-explorer')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('workspace-layout-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Classic'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('focus-workspace-layout')), findsNothing);
    expect(
      find.byKey(const ValueKey('classic-codex-workspace-layout')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('classic menampilkan sidebar navigasi dan actions chat', (
    tester,
  ) async {
    _setMockPreferences({});
    await tester.binding.setSurfaceSize(const Size(1500, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KodeAgentApp());
    await _pumpLoaded(tester);

    for (final label in const [
      'YOUNZCODE',
      'New Chat',
      'Pull Requests',
      'Scheduled',
      'Plugins',
      'Browser',
      'Images',
      'Terminal',
      'History',
      'Add-ons',
      'PROJECT',
      'RECENTS',
      'Mulai chat pertama',
    ]) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    expect(find.byKey(const ValueKey('classic-sidebar')), findsOneWidget);
    expect(find.byTooltip('Menu workspace'), findsNothing);
    final subagentButton = find.byKey(const ValueKey('classic-subagent'));
    if (subagentButton.evaluate().isNotEmpty) {
      await tester.tap(subagentButton);
    } else {
      expect(find.byKey(const ValueKey('composer-tools-menu')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('composer-tools-menu')));
      await tester.pump(const Duration(seconds: 1));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    }
    await tester.pump();
    final prompt = tester.widget<TextField>(
      find.byKey(const ValueKey('prompt-field')),
    );
    expect(prompt.controller?.text, '/agents ');
    expect(tester.takeException(), isNull);
  });

  testWidgets('classic sidebar dapat diciutkan menjadi icon rail', (
    tester,
  ) async {
    _setMockPreferences({});
    await tester.binding.setSurfaceSize(const Size(1500, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KodeAgentApp());
    await _pumpLoaded(tester);

    final sidebar = find.byKey(const ValueKey('classic-sidebar'));
    expect(tester.getSize(sidebar).width, closeTo(266, 0.5));
    await tester.tap(find.byKey(const ValueKey('classic-sidebar-toggle')));
    await tester.pumpAndSettle();

    expect(tester.getSize(sidebar).width, closeTo(72, 0.5));
    expect(find.text('PROJECT'), findsNothing);
    expect(find.byTooltip('Browser'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('classic-sidebar-toggle')));
    await tester.pumpAndSettle();
    expect(tester.getSize(sidebar).width, closeTo(266, 0.5));
    expect(
      find.byKey(const ValueKey('workspace-layout-picker')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('command palette dapat dicari melalui Ctrl+K', (tester) async {
    _setMockPreferences({});
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KodeAgentApp());
    await _pumpLoaded(tester);

    await tester.tap(find.byKey(const ValueKey('prompt-field')));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(find.text('COMMAND PALETTE'), findsOneWidget);
    final search = find.byKey(const ValueKey('command-palette-search'));
    expect(search, findsOneWidget);
    await tester.enterText(search, 'retry');
    await tester.pump();
    expect(find.text('Prepare Retry Prompt'), findsOneWidget);
    expect(find.text('Open File'), findsNothing);
    await tester.tap(find.text('Prepare Retry Prompt'));
    await tester.pumpAndSettle();
    expect(
      find.text('Belum ada prompt pengguna yang bisa diulang.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('slash menu menampilkan aksi retry dan continue yang aman', (
    tester,
  ) async {
    _setMockPreferences({});
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KodeAgentApp());
    await _pumpLoaded(tester);

    final field = find.byKey(const ValueKey('prompt-field'));
    await tester.enterText(field, '/');
    await tester.pump();
    expect(find.byKey(const ValueKey('slash-command-retry')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('slash-command-continue')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('slash-command-retry')));
    await tester.pump();
    expect(
      find.text('Belum ada prompt pengguna yang bisa diulang.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('send-agent')), findsOneWidget);
    expect(find.byKey(const ValueKey('composer-shortcuts')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('status bar tetap aman pada viewport sempit', (tester) async {
    _setMockPreferences({});
    await tester.binding.setSurfaceSize(const Size(580, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KodeAgentApp());
    await _pumpLoaded(tester);

    expect(find.byKey(const ValueKey('classic-sidebar')), findsNothing);
    expect(find.byKey(const ValueKey('status-bar')), findsOneWidget);
    expect(find.byKey(const ValueKey('status-summary-chip')), findsOneWidget);
    expect(tester.getSize(find.byKey(const ValueKey('status-bar'))).width, 580);
    expect(tester.takeException(), isNull);
  });

  testWidgets('status chip membuka penjelasan dan tindakan setup', (
    tester,
  ) async {
    _setMockPreferences({});
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KodeAgentApp());
    await _pumpLoaded(tester);

    await tester.tap(find.byKey(const ValueKey('status-summary-chip')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('workspace-status-dialog')),
      findsOneWidget,
    );
    expect(find.text('Provider belum dikonfigurasi'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('status-choose-workspace')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('status-configure-provider')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('environment menampilkan git, processes, dan sources', (
    tester,
  ) async {
    _setMockPreferences({});
    await tester.binding.setSurfaceSize(const Size(1500, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KodeAgentApp());
    await _pumpLoaded(tester);

    expect(find.text('ENVIRONMENT'), findsOneWidget);
    expect(find.text('Changes'), findsOneWidget);
    expect(find.text('Processes'), findsOneWidget);
    expect(find.text('Sources'), findsOneWidget);
    expect(find.byKey(const ValueKey('environment-add-source')), findsNothing);
    final environmentCard = tester.widget<Material>(
      find.byKey(const ValueKey('classic-environment-panel')),
    );
    expect(environmentCard.elevation, greaterThan(0));
    expect(environmentCard.borderRadius, BorderRadius.circular(16));
    expect(
      Theme.of(
        tester.element(find.byKey(const ValueKey('classic-environment-panel'))),
      ).dividerColor,
      Colors.transparent,
    );
    await tester.tap(find.byKey(const ValueKey('environment-summary-card')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('environment-details-dialog')),
      findsOneWidget,
    );
    expect(find.text('Local'), findsOneWidget);
    expect(find.text('Commit or push'), findsOneWidget);
    expect(find.text('Compare branch'), findsOneWidget);
    expect(find.text('BACKGROUND PROCESSES'), findsOneWidget);
    expect(find.text('SOURCES'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('about menjelaskan fitur utama YOUNZCODE 2.0', (tester) async {
    _setMockPreferences({});
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KodeAgentApp());
    await _pumpLoaded(tester);

    await tester.tap(find.byKey(const ValueKey('classic-about-button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('younzcode-about-dialog')),
      findsOneWidget,
    );
    expect(find.text('YOUNZCODE 2.0'), findsOneWidget);
    expect(find.text('Dua tampilan workspace'), findsOneWidget);
    expect(find.text('Respons agent bertahap'), findsOneWidget);
    expect(find.text('Provider AI fleksibel'), findsOneWidget);
    expect(find.text('Plugins dan Subagent'), findsOneWidget);
    expect(find.text('Environment dan perubahan'), findsOneWidget);
    expect(find.text('Build v2.0.0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('focus menampilkan agent tanpa activity panel lama', (
    tester,
  ) async {
    _setMockPreferences({'workspace_layout': 'focus'});
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KodeAgentApp());
    await _pumpLoaded(tester);

    expect(find.byKey(const ValueKey('focus-agent-panel')), findsOneWidget);
    expect(find.byKey(const ValueKey('activity-panel')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('explorer focus dapat diubah ukurannya', (tester) async {
    _setMockPreferences({'workspace_layout': 'focus'});
    await tester.binding.setSurfaceSize(const Size(1400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KodeAgentApp());
    await _pumpLoaded(tester);

    final explorer = find.byKey(const ValueKey('workspace-explorer'));
    final explorerBefore = tester.getSize(explorer).width;

    await tester.drag(
      find.byKey(const ValueKey('focus-explorer-resize-handle')),
      const Offset(60, 0),
    );
    await tester.pump();

    expect(tester.getSize(explorer).width, greaterThan(explorerBefore));
    expect(tester.takeException(), isNull);
  });

  testWidgets('explorer dapat disembunyikan dan ditampilkan kembali', (
    tester,
  ) async {
    _setMockPreferences({'workspace_layout': 'focus'});
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KodeAgentApp());
    await _pumpLoaded(tester);

    final explorer = find.byKey(const ValueKey('workspace-explorer'));
    expect(explorer, findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('hide-explorer-panel')));
    await tester.pumpAndSettle();
    expect(explorer, findsNothing);
    expect(
      find.byKey(const ValueKey('focus-workspace-layout')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('classic-sidebar')), findsNothing);

    await tester.tap(find.text('Explorer'));
    await tester.pumpAndSettle();
    expect(explorer, findsOneWidget);
    expect(
      find.byKey(const ValueKey('focus-workspace-layout')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('notification dapat dibuka dan dihapus', (tester) async {
    final workspace = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('younzcode-notification-'),
    ))!;
    addTearDown(() => tester.runAsync(() => workspace.delete(recursive: true)));
    _setMockPreferences({
      'workspace': workspace.path,
      'workspace_layout': 'focus',
    });
    await tester.binding.setSurfaceSize(const Size(1400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KodeAgentApp());
    await _pumpLoaded(tester);

    await tester.tap(find.byKey(const ValueKey('restricted-mode-action')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('trust-current-workspace')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byKey(const ValueKey('notifications-button')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Workspace trusted'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('notification-item-0')));
    await tester.pump();
    expect(find.byKey(const ValueKey('notification-detail')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('delete-notification-0')));
    await tester.pump();
    expect(find.text('No notifications.'), findsOneWidget);
    expect(find.byKey(const ValueKey('notification-detail')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('.env dapat dibuka lokal setelah konfirmasi', (tester) async {
    final workspace = (await tester.runAsync(() async {
      final directory = await Directory.systemTemp.createTemp('younzcode-env-');
      await File(
        '${directory.path}${Platform.pathSeparator}.env',
      ).writeAsString('SECRET=local-only');
      return directory;
    }))!;
    addTearDown(() => tester.runAsync(() => workspace.delete(recursive: true)));
    _setMockPreferences({
      'workspace': workspace.path,
      'workspace_layout': 'focus',
    });
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KodeAgentApp());
    await _pumpLoaded(tester);

    final environmentFile = find.text('.env');
    await _pumpUntilFound(tester, environmentFile);
    await tester.tap(environmentFile);
    await tester.pumpAndSettle();
    expect(find.text('Buka file environment?'), findsOneWidget);
    expect(find.text('BUKA LOKAL'), findsOneWidget);

    await tester.tap(find.text('BUKA LOKAL'));
    final editor = find.byKey(const ValueKey('workspace-editor'));
    await _pumpUntilFound(tester, editor);
    expect(editor, findsOneWidget);
    expect(
      find.byTooltip('File sensitif lokal; agent AI tetap diblokir'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('riwayat chat tersimpan dapat dibuka kembali', (tester) async {
    final workspace = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('younzcode-chat-'),
    ))!;
    addTearDown(() => tester.runAsync(() => workspace.delete(recursive: true)));
    _setMockPreferences({
      'workspace': workspace.path,
      'workspace_layout': 'focus',
    });
    await ChatSessionStore().save([
      ChatSession(
        id: 'saved-chat',
        workspace: workspace.path,
        updatedAt: DateTime(2026, 7, 23, 10),
        entries: const [
          ChatEntry(role: ChatRole.user, content: 'Percakapan tersimpan'),
          ChatEntry(role: ChatRole.assistant, content: 'Masih tersedia'),
        ],
      ),
    ]);
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KodeAgentApp());
    await _pumpLoaded(tester);

    expect(find.text('Percakapan tersimpan'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('rail-history')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('CHAT HISTORY'), findsOneWidget);
    expect(find.text('Percakapan tersimpan'), findsWidgets);
    expect(find.textContaining('2 pesan'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('chat-session-saved-chat')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Masih tersedia'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('history dapat dicari, dipin, diganti nama, dan dihapus', (
    tester,
  ) async {
    final workspace = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('younzcode-history-actions-'),
    ))!;
    addTearDown(() => tester.runAsync(() => workspace.delete(recursive: true)));
    _setMockPreferences({
      'workspace': workspace.path,
      'workspace_layout': 'focus',
    });
    await ChatSessionStore().save([
      ChatSession(
        id: 'history-alpha',
        workspace: workspace.path,
        updatedAt: DateTime(2026, 7, 23, 10),
        entries: const [
          ChatEntry(role: ChatRole.user, content: 'Alpha conversation'),
          ChatEntry(role: ChatRole.assistant, content: 'Alpha response'),
        ],
      ),
      ChatSession(
        id: 'history-beta',
        workspace: workspace.path,
        updatedAt: DateTime(2026, 7, 24, 10),
        entries: const [
          ChatEntry(role: ChatRole.user, content: 'Beta conversation'),
          ChatEntry(role: ChatRole.assistant, content: 'Beta response'),
        ],
      ),
    ]);
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KodeAgentApp());
    await _pumpLoaded(tester);

    await tester.tap(find.byKey(const ValueKey('rail-history')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.byKey(const ValueKey('chat-session-history-alpha')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('chat-session-history-beta')),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey('history-search')),
      'Alpha',
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('chat-session-history-alpha')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('chat-session-history-beta')),
      findsNothing,
    );

    await tester.enterText(find.byKey(const ValueKey('history-search')), '');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chat-menu-history-alpha')));
    await tester.pump(const Duration(seconds: 1));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await _pumpLoaded(tester);
    expect(find.byIcon(Icons.push_pin), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('chat-menu-history-alpha')));
    await tester.pump(const Duration(seconds: 1));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(
      find.byKey(const ValueKey('history-rename-field')),
      'Alpha renamed',
    );
    await tester.tap(find.text('SIMPAN'));
    await _pumpLoaded(tester);
    expect(find.text('Alpha renamed'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('chat-menu-history-beta')));
    await tester.pump(const Duration(seconds: 1));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('HAPUS CHAT?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('history-delete-confirm')));
    await _pumpLoaded(tester);
    expect(
      find.byKey(const ValueKey('chat-session-history-beta')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('respons agent dapat disalin dalam format yang terlihat', (
    tester,
  ) async {
    final workspace = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('younzcode-copy-'),
    ))!;
    addTearDown(() => tester.runAsync(() => workspace.delete(recursive: true)));
    _setMockPreferences({'workspace': workspace.path});
    await ChatSessionStore().save([
      ChatSession(
        id: 'copy-chat',
        workspace: workspace.path,
        updatedAt: DateTime(2026, 7, 24, 10),
        entries: const [
          ChatEntry(role: ChatRole.user, content: 'Tolong periksa'),
          ChatEntry(
            role: ChatRole.assistant,
            content: '## Hasil\n```text\n- Semua lulus\n```',
          ),
        ],
      ),
    ]);
    String? copiedText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KodeAgentApp());
    await _pumpLoaded(tester);

    expect(find.byKey(const ValueKey('copy-agent-response')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('copy-agent-response-bottom')),
      findsOneWidget,
    );
    expect(find.text('COPY RESPONSE'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('copy-agent-response-bottom')));
    await tester.pump();

    expect(copiedText, 'Hasil\n\n- Semua lulus');
    expect(find.text('Respons disalin.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('kartu percakapan tetap rapat dan terpusat pada layar lebar', (
    tester,
  ) async {
    final workspace = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('younzcode-chat-lane-'),
    ))!;
    addTearDown(() => tester.runAsync(() => workspace.delete(recursive: true)));
    _setMockPreferences({'workspace': workspace.path});
    await ChatSessionStore().save([
      ChatSession(
        id: 'wide-chat',
        workspace: workspace.path,
        updatedAt: DateTime(2026, 7, 27),
        entries: const [
          ChatEntry(role: ChatRole.user, content: 'Lanjutkan'),
          ChatEntry(
            role: ChatRole.assistant,
            content: 'Saya akan melanjutkan pekerjaan.',
          ),
        ],
      ),
    ]);
    const surfaceSize = Size(1920, 1080);
    await tester.binding.setSurfaceSize(surfaceSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KodeAgentApp());
    await _pumpLoaded(tester);

    final userRect = tester.getRect(
      find.byKey(const ValueKey('user-message-card')),
    );
    final agentRect = tester.getRect(
      find.byKey(const ValueKey('agent-message-card')),
    );
    final combinedCenter = (userRect.center.dx + agentRect.center.dx) / 2;

    expect(userRect.width, lessThanOrEqualTo(760));
    expect(agentRect.width, lessThanOrEqualTo(760));
    expect((combinedCenter - surfaceSize.width / 2).abs(), lessThan(180));
    expect(userRect.left, lessThan(agentRect.right));
    expect(tester.takeException(), isNull);
  });

  testWidgets('riwayat panjang otomatis menampilkan respons terbaru', (
    tester,
  ) async {
    final workspace = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('younzcode-scroll-'),
    ))!;
    addTearDown(() => tester.runAsync(() => workspace.delete(recursive: true)));
    _setMockPreferences({'workspace': workspace.path});
    await ChatSessionStore().save([
      ChatSession(
        id: 'scroll-chat',
        workspace: workspace.path,
        updatedAt: DateTime(2026, 7, 24, 11),
        entries: [
          for (var index = 0; index < 24; index++)
            ChatEntry(
              role: index.isEven ? ChatRole.user : ChatRole.assistant,
              content: index == 23 ? 'RESPONS PALING BARU' : 'Pesan $index',
            ),
        ],
      ),
    ]);
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KodeAgentApp());
    await _pumpLoaded(tester);
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('RESPONS PALING BARU'), findsOneWidget);
    final conversation = tester.widget<ListView>(
      find.byKey(const ValueKey('conversation-list')),
    );
    expect(conversation.reverse, isTrue);
    expect(
      conversation.controller?.offset,
      conversation.controller?.position.minScrollExtent,
    );
    expect(
      tester.getBottomRight(find.text('RESPONS PALING BARU')).dy,
      lessThan(700),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('light mode dapat diaktifkan dan disimpan', (tester) async {
    _setMockPreferences({'workspace_layout': 'focus'});
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KodeAgentApp());
    await _pumpLoaded(tester);

    expect(
      Theme.of(tester.element(find.byType(Scaffold).first)).brightness,
      Brightness.dark,
    );
    await tester.tap(find.byKey(const ValueKey('theme-toggle')));
    await tester.pumpAndSettle();

    expect(
      Theme.of(tester.element(find.byType(Scaffold).first)).brightness,
      Brightness.light,
    );
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getBool('light_mode'), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('light mode memakai teks dan popup dengan kontras terang', (
    tester,
  ) async {
    final workspace = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('younzcode-light-theme-'),
    ))!;
    addTearDown(() => tester.runAsync(() => workspace.delete(recursive: true)));
    final canonicalWorkspace = (await tester.runAsync(
      workspace.resolveSymbolicLinks,
    ))!;
    _setMockPreferences({
      'light_mode': true,
      'workspace': workspace.path,
      'trusted_workspaces': [canonicalWorkspace],
      'workspace_layout': 'focus',
    });
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KodeAgentApp());
    await _pumpLoaded(tester);

    final context = tester.element(find.byType(Scaffold).first);
    final theme = Theme.of(context);
    expect(theme.brightness, Brightness.light);
    final workspaceLabel = tester.widget<Text>(find.text('WORKSPACE').first);
    expect(workspaceLabel.style?.color, theme.colorScheme.onSurfaceVariant);
    final statusBar = tester.widget<Container>(
      find.byKey(const ValueKey('status-bar')),
    );
    final statusDecoration = statusBar.decoration! as BoxDecoration;
    expect(statusDecoration.color, theme.colorScheme.surface);

    await tester.tap(find.byKey(const ValueKey('rail-terminal')));
    await tester.pump(const Duration(milliseconds: 300));
    final terminal = tester.widget<Container>(
      find.byKey(const ValueKey('integrated-terminal')),
    );
    final terminalDecoration = terminal.decoration! as BoxDecoration;
    expect(terminalDecoration.color, theme.colorScheme.surface);

    await tester.tap(find.byKey(const ValueKey('manage-models-compact')));
    await tester.pump(const Duration(milliseconds: 300));
    final dialog = tester.widget<Dialog>(find.byType(Dialog));
    expect(dialog.backgroundColor, theme.colorScheme.surface);
    expect(tester.takeException(), isNull);
  });

  testWidgets('file tree light mode memakai warna tema yang kontras', (
    tester,
  ) async {
    final workspace = (await tester.runAsync(() async {
      final directory = await Directory.systemTemp.createTemp(
        'younzcode-light-tree-',
      );
      await Directory('${directory.path}${Platform.pathSeparator}lib').create();
      await File(
        '${directory.path}${Platform.pathSeparator}visible.txt',
      ).writeAsString('visible');
      return directory;
    }))!;
    addTearDown(() => tester.runAsync(() => workspace.delete(recursive: true)));
    _setMockPreferences({
      'workspace': workspace.path,
      'light_mode': true,
      'onboarding_complete': true,
      'workspace_layout': 'focus',
    });
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KodeAgentApp());
    await _pumpLoaded(tester);

    await _pumpUntilFound(tester, find.text('visible.txt'));
    final theme = Theme.of(tester.element(find.byType(Scaffold).first));
    final folder = tester.widget<Text>(find.text('lib'));
    final file = tester.widget<Text>(find.text('visible.txt'));
    expect(folder.style?.color, theme.colorScheme.onSurface);
    expect(file.style?.color, theme.colorScheme.onSurfaceVariant);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editor file light mode memakai kanvas dan teks terang', (
    tester,
  ) async {
    final workspace = (await tester.runAsync(() async {
      final directory = await Directory.systemTemp.createTemp(
        'younzcode-light-editor-',
      );
      await File(
        '${directory.path}${Platform.pathSeparator}sample.txt',
      ).writeAsString('Isi file terlihat');
      return directory;
    }))!;
    addTearDown(() => tester.runAsync(() => workspace.delete(recursive: true)));
    _setMockPreferences({
      'workspace': workspace.path,
      'light_mode': true,
      'onboarding_complete': true,
      'workspace_layout': 'focus',
    });
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KodeAgentApp());
    await _pumpLoaded(tester);

    final fileName = find.text('sample.txt');
    await _pumpUntilFound(tester, fileName);
    await tester.tap(fileName);
    final editorFinder = find.byKey(const ValueKey('workspace-editor'));
    await _pumpUntilFound(tester, editorFinder);

    final theme = Theme.of(tester.element(editorFinder));
    final editor = tester.widget<TextField>(editorFinder);
    expect(editor.style?.color, theme.colorScheme.onSurface);
    expect(editor.decoration?.fillColor, const Color(0xFFFFFFFF));
    expect(editor.controller?.text, 'Isi file terlihat');

    await tester.tap(find.byTooltip('Back to Chat'));
    await tester.pumpAndSettle();
    expect(editorFinder, findsNothing);

    await tester.tap(find.text('Editor'));
    await tester.pumpAndSettle();
    expect(editorFinder, findsOneWidget);
    await tester.tap(editorFinder);
    await tester.enterText(editorFinder, 'Isi file telah diedit');
    expect(
      tester.widget<TextField>(editorFinder).controller?.text,
      'Isi file telah diedit',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('restricted editor blocks analyze and debug execution', (
    tester,
  ) async {
    final workspace = (await tester.runAsync(() async {
      final directory = await Directory.systemTemp.createTemp(
        'younzcode-restricted-editor-',
      );
      await File(
        '${directory.path}${Platform.pathSeparator}sample.dart',
      ).writeAsString('void main() {}');
      return directory;
    }))!;
    addTearDown(() => tester.runAsync(() => workspace.delete(recursive: true)));
    _setMockPreferences({
      'workspace': workspace.path,
      'workspace_layout': 'focus',
    });
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KodeAgentApp());
    await _pumpLoaded(tester);

    await _pumpUntilFound(tester, find.text('sample.dart'));
    await tester.tap(find.text('sample.dart'));
    await _pumpUntilFound(
      tester,
      find.byKey(const ValueKey('workspace-editor')),
    );

    final analyze = tester.widget<IconButton>(
      find.byKey(const ValueKey('analyze-editor-file')),
    );
    final debug = tester.widget<IconButton>(
      find.byKey(const ValueKey('start-debugger')),
    );
    expect(analyze.onPressed, isNull);
    expect(debug.onPressed, isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.f5);
    await tester.pump();
    expect(find.text('DEBUG CONSOLE'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('root file tree dapat dibuka dan ditutup', (tester) async {
    final workspace = (await tester.runAsync(() async {
      final directory = await Directory.systemTemp.createTemp(
        'younzcode-root-',
      );
      await File(
        '${directory.path}${Platform.pathSeparator}visible.txt',
      ).writeAsString('visible');
      return directory;
    }))!;
    addTearDown(() => tester.runAsync(() => workspace.delete(recursive: true)));
    _setMockPreferences({
      'workspace': workspace.path,
      'workspace_layout': 'focus',
    });
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KodeAgentApp());
    await _pumpLoaded(tester);

    final visibleFile = find.text('visible.txt');
    await _pumpUntilFound(tester, visibleFile);
    expect(visibleFile, findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('workspace-tree-root-toggle')));
    await tester.pumpAndSettle();
    expect(visibleFile, findsNothing);
    await tester.tap(find.byKey(const ValueKey('workspace-tree-root-toggle')));
    await _pumpUntilFound(tester, visibleFile);
    expect(visibleFile, findsOneWidget);
  });

  testWidgets('restricted workspace dapat dipercaya dari status bar', (
    tester,
  ) async {
    final workspace = (await tester.runAsync(() async {
      return Directory.systemTemp.createTemp('younzcode-trust-');
    }))!;
    addTearDown(() => tester.runAsync(() => workspace.delete(recursive: true)));
    _setMockPreferences({
      'workspace': workspace.path,
      'onboarding_complete': true,
    });
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KodeAgentApp());
    await _pumpLoaded(tester);

    final restricted = find.byKey(const ValueKey('restricted-mode-action'));
    expect(restricted, findsOneWidget);
    await tester.tap(restricted);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('trust-current-workspace')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(restricted, findsNothing);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getStringList('trusted_workspaces'), isNotEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('plan mode dapat dipilih dari composer', (tester) async {
    _setMockPreferences({});
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KodeAgentApp());
    await _pumpLoaded(tester);

    await tester.tap(find.byKey(const ValueKey('agent-mode-selector')));
    await tester.pumpAndSettle();
    expect(find.textContaining('READ-ONLY'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('slash command update-status menampilkan diagnostik update', (
    tester,
  ) async {
    _setMockPreferences({});
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KodeAgentApp());
    await _pumpLoaded(tester);

    final field = find.byKey(const ValueKey('prompt-field'));
    await tester.tap(field);
    await tester.enterText(field, '/update-status');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.text('UPDATE & SIGNING DIAGNOSTICS'), findsOneWidget);
    expect(find.text('TRUSTED SIGNING KEYS (2)'), findsOneWidget);
    // The two trusted keys are listed (full base64 selectable).
    expect(find.textContaining('VERIFIED LAST'), findsNothing);
    expect(find.textContaining('Latency'), findsNothing);
    expect(
      find.text('Belum ada pemeriksaan update di sesi ini.'),
      findsOneWidget,
    );
    expect(find.text('CLOSE'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Closing the dialog leaves the app intact.
    await tester.tap(find.text('CLOSE'));
    await tester.pumpAndSettle();
    expect(find.text('UPDATE & SIGNING DIAGNOSTICS'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
