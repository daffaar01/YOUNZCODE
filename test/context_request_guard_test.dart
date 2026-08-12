import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kode_agent_desktop/services/context_request_guard.dart';

void main() {
  test(
    'lease rejects ABA workspace and replacement engine identities',
    () async {
      final first = await Directory.systemTemp.createTemp('lease-first-');
      final second = await Directory.systemTemp.createTemp('lease-second-');
      addTearDown(() async {
        await first.delete(recursive: true);
        await second.delete(recursive: true);
      });
      final engine = Object();
      var workspace = first.path;
      final lease = await ContextRequestLease.capture(
        workspace: workspace,
        trusted: true,
        engine: engine,
      );

      workspace = second.path;
      workspace = first.path;
      final replacementEngine = Object();

      expect(
        await lease.isCurrent(
          workspace: workspace,
          trusted: true,
          engine: replacementEngine,
        ),
        isFalse,
      );
    },
  );

  test('lease rejects canonical retargeting and revoked trust', () async {
    final first = await Directory.systemTemp.createTemp('lease-first-');
    final second = await Directory.systemTemp.createTemp('lease-second-');
    final link = Link(
      '${first.parent.path}${Platform.pathSeparator}lease-link-${DateTime.now().microsecondsSinceEpoch}',
    );
    addTearDown(() async {
      if (await link.exists()) await link.delete();
      await first.delete(recursive: true);
      await second.delete(recursive: true);
    });
    try {
      await link.create(first.path);
    } on FileSystemException {
      return;
    }
    final engine = Object();
    final lease = await ContextRequestLease.capture(
      workspace: link.path,
      trusted: true,
      engine: engine,
    );
    await link.delete();
    await link.create(second.path);

    expect(
      await lease.isCurrent(
        workspace: link.path,
        trusted: true,
        engine: engine,
      ),
      isFalse,
    );
    expect(
      await lease.isCurrent(
        workspace: link.path,
        trusted: false,
        engine: engine,
      ),
      isFalse,
    );
  });
}
