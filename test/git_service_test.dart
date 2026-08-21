@Tags(['slow'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kode_agent_desktop/services/git_service.dart';

void main() {
  test('stage, unstage, commit, branch, dan status bekerja', () async {
    final root = await Directory.systemTemp.createTemp('younz-git-');
    addTearDown(() => root.delete(recursive: true));
    await _git(root.path, ['init']);
    await _git(root.path, ['config', 'user.email', 'test@example.com']);
    await _git(root.path, ['config', 'user.name', 'YOUNZ Test']);
    final file = File('${root.path}${Platform.pathSeparator}sample.txt');
    await file.writeAsString('one\n');
    await _git(root.path, ['add', 'sample.txt']);
    await _git(root.path, ['commit', '-m', 'initial']);
    final service = const GitService();

    await file.writeAsString('two\n');
    var status = await service.status(root.path);
    expect(status.entries.single.unstaged, isTrue);

    await service.stage(root.path, ['sample.txt']);
    status = await service.status(root.path);
    expect(status.entries.single.staged, isTrue);

    await service.unstage(root.path, ['sample.txt']);
    status = await service.status(root.path);
    expect(status.entries.single.unstaged, isTrue);

    await service.stage(root.path, ['sample.txt']);
    await service.commit(root.path, 'change sample');
    expect((await service.status(root.path)).dirty, isFalse);

    await service.createBranch(root.path, 'codex/test-branch');
    expect((await service.status(root.path)).branch, 'codex/test-branch');
    expect(await service.branches(root.path), contains('codex/test-branch'));
    expect((await service.syncStatus(root.path)).hasUpstream, isFalse);
  });

  test('sync status menampilkan commit ahead dari upstream', () async {
    final root = await Directory.systemTemp.createTemp('younz-git-sync-');
    final remote = await Directory.systemTemp.createTemp('younz-git-remote-');
    addTearDown(() async {
      await root.delete(recursive: true);
      await remote.delete(recursive: true);
    });
    await _git(remote.path, ['init', '--bare']);
    await _git(root.path, ['init']);
    await _git(root.path, ['config', 'user.email', 'test@example.com']);
    await _git(root.path, ['config', 'user.name', 'YOUNZ Test']);
    await File(
      '${root.path}${Platform.pathSeparator}sample.txt',
    ).writeAsString('one\n');
    await _git(root.path, ['add', 'sample.txt']);
    await _git(root.path, ['commit', '-m', 'initial']);
    await _git(root.path, ['remote', 'add', 'origin', remote.path]);
    await _git(root.path, ['push', '-u', 'origin', 'HEAD']);

    final service = const GitService();
    expect((await service.syncStatus(root.path)).synced, isTrue);

    await File(
      '${root.path}${Platform.pathSeparator}sample.txt',
    ).writeAsString('two\n');
    await _git(root.path, ['add', 'sample.txt']);
    await _git(root.path, ['commit', '-m', 'ahead']);
    final sync = await service.syncStatus(root.path);
    expect(sync.ahead, 1);
    expect(sync.behind, 0);
  });

  test('diff mengabaikan untracked malformed UTF-8 tanpa gagal', () async {
    final root = await Directory.systemTemp.createTemp('younz-git-');
    addTearDown(() => root.delete(recursive: true));
    await _git(root.path, ['init']);
    await File(
      '${root.path}${Platform.pathSeparator}invalid.dart',
    ).writeAsBytes([0xC3, 0x28]);

    expect(await const GitService().diff(root.path), isEmpty);
  });

  test('diff tidak membaca symlink untracked di luar workspace', () async {
    final root = await Directory.systemTemp.createTemp('younz-git-');
    final outside = await Directory.systemTemp.createTemp('younz-secret-');
    addTearDown(() async {
      await root.delete(recursive: true);
      await outside.delete(recursive: true);
    });
    await _git(root.path, ['init']);
    final secret = File('${outside.path}${Platform.pathSeparator}secret.dart');
    await secret.writeAsString('const leaked = "outside-secret";\n');
    final link = Link('${root.path}${Platform.pathSeparator}linked.dart');
    try {
      await link.create(secret.path);
    } on FileSystemException {
      return;
    }

    expect(
      await const GitService().diff(root.path),
      isNot(contains('outside-secret')),
    );
  });

  test(
    'diff untracked kosong dan tanpa final newline tetap Git-valid',
    () async {
      final root = await Directory.systemTemp.createTemp('younz-git-');
      addTearDown(() => root.delete(recursive: true));
      await _git(root.path, ['init']);
      final empty = File('${root.path}${Platform.pathSeparator}empty.txt');
      final noNewline = File(
        '${root.path}${Platform.pathSeparator}no-newline.txt',
      );
      await empty.writeAsString('');
      await noNewline.writeAsString('without newline');

      final diff = await const GitService().diff(root.path);
      await empty.delete();
      await noNewline.delete();

      expect(diff, contains('empty.txt'));
      expect(diff, contains(r'\ No newline at end of file'));
      expect(await _gitApplyCheck(root.path, diff), 0);
    },
  );

  test('diff menyertakan file untracked secara bounded', () async {
    final root = await Directory.systemTemp.createTemp('younz-git-');
    addTearDown(() => root.delete(recursive: true));
    await _git(root.path, ['init']);
    await File(
      '${root.path}${Platform.pathSeparator}new file.dart',
    ).writeAsString('void main() {}\n');
    await File(
      '${root.path}${Platform.pathSeparator}binary.bin',
    ).writeAsBytes([0, 1, 2]);

    final diff = await const GitService().diff(root.path);

    expect(diff, contains('diff --git a/new file.dart b/new file.dart'));
    expect(diff, contains('+void main() {}'));
    expect(diff, isNot(contains('binary.bin')));
  });

  test(
    'diff tracked menghitung staged dan unstaged dalam budget file yang sama',
    () async {
      final root = await Directory.systemTemp.createTemp('younz-git-');
      addTearDown(() => root.delete(recursive: true));
      await _git(root.path, ['init']);
      await _git(root.path, ['config', 'user.email', 'test@example.com']);
      await _git(root.path, ['config', 'user.name', 'YOUNZ Test']);
      final file = File('${root.path}${Platform.pathSeparator}both.txt');
      await file.writeAsString('base\n');
      await _git(root.path, ['add', 'both.txt']);
      await _git(root.path, ['commit', '-m', 'initial']);
      await file.writeAsString(List.filled(1500, 'staged-change').join('\n'));
      await _git(root.path, ['add', 'both.txt']);
      await file.writeAsString(List.filled(1500, 'unstaged-change').join('\n'));

      final diff = await const GitService().diff(root.path);

      expect(diff, contains('REVIEW-DIFF-OMITTED both.txt'));
      expect(diff.length, lessThanOrEqualTo(gitDiffPerFileMaxChars + 64));
    },
  );

  test(
    'diff tracked membatasi per-file dan melaporkan omission deterministik',
    () async {
      final root = await Directory.systemTemp.createTemp('younz-git-');
      addTearDown(() => root.delete(recursive: true));
      await _git(root.path, ['init']);
      await _git(root.path, ['config', 'user.email', 'test@example.com']);
      await _git(root.path, ['config', 'user.name', 'YOUNZ Test']);
      for (final name in ['z.txt', 'a.txt']) {
        await File(
          '${root.path}${Platform.pathSeparator}$name',
        ).writeAsString('base\n');
      }
      await _git(root.path, ['add', '.']);
      await _git(root.path, ['commit', '-m', 'initial']);
      final oversized = List.filled(
        gitDiffPerFileMaxChars,
        'changed',
      ).join('\n');
      await File(
        '${root.path}${Platform.pathSeparator}z.txt',
      ).writeAsString(oversized);
      await File(
        '${root.path}${Platform.pathSeparator}a.txt',
      ).writeAsString(oversized);

      final diff = await const GitService().diff(root.path);

      expect(diff.length, lessThanOrEqualTo(gitDiffAggregateMaxChars));
      expect(diff, contains('REVIEW-DIFF-OMITTED a.txt'));
      expect(diff, contains('REVIEW-DIFF-OMITTED z.txt'));
      expect(
        diff.indexOf('REVIEW-DIFF-OMITTED a.txt'),
        lessThan(diff.indexOf('REVIEW-DIFF-OMITTED z.txt')),
      );
    },
  );
}

Future<int> _gitApplyCheck(String workspace, String patch) async {
  final process = await Process.start('git', [
    'apply',
    '--check',
    '-',
  ], workingDirectory: workspace);
  process.stdin.write(patch);
  await process.stdin.close();
  return process.exitCode;
}

Future<void> _git(String workspace, List<String> arguments) async {
  final result = await Process.run(
    'git',
    arguments,
    workingDirectory: workspace,
  );
  if (result.exitCode != 0) {
    throw ProcessException('git', arguments, '${result.stderr}');
  }
}
