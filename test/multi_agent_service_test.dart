@Tags(['slow'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kode_agent_desktop/models/task_graph.dart';
import 'package:kode_agent_desktop/services/multi_agent_service.dart';

void main() {
  test('hasil multi-agent diformat sebagai respons chat', () {
    final tasks = [
      const AgentTask(
        id: 'a',
        nodeId: 'agent-0',
        prompt: 'Periksa bug',
        status: AgentTaskStatus.completed,
        branch: 'codex/agent-bug',
        result: 'Tidak menemukan bug kritis.',
      ),
      const AgentTask(
        id: 'b',
        nodeId: 'agent-1',
        prompt: 'Periksa kualitas',
        status: AgentTaskStatus.failed,
        error: 'Timeout setelah 30 menit.',
      ),
    ];

    final message = formatMultiAgentResultsForChat(tasks);

    expect(message, contains('MULTI-AGENT RESULTS — 1/2 selesai'));
    expect(message, contains('1. ✅ Periksa bug'));
    expect(message, contains('Tidak menemukan bug kritis.'));
    expect(message, contains('2. ❌ Periksa kualitas'));
    expect(message, contains('Timeout setelah 30 menit.'));
    expect(message, isNot(contains(r'C:\Users')));
  });

  test(
    'multi-agent max mendapat deadline panjang dan satu attempt di 9Router',
    () {
      expect(
        multiAgentRequestTimeoutMs(
          model: 'cx/gpt-5.6-sol(max)',
          configuredTimeoutMs: 120000,
        ),
        600000,
      );
      expect(
        multiAgentTurnDuration('cx/gpt-5.6-sol(max)'),
        const Duration(minutes: 30),
      );
      expect(multiAgentRequestAttempts('http://127.0.0.1:20128/v1'), 1);
      expect(multiAgentMaxParallel('http://127.0.0.1:20128/v1'), 1);
    },
  );

  test('multi-agent non-max mempertahankan konfigurasi umum', () {
    expect(
      multiAgentRequestTimeoutMs(
        model: 'cx/gpt-5.6-sol',
        configuredTimeoutMs: 180000,
      ),
      180000,
    );
    expect(
      multiAgentTurnDuration('cx/gpt-5.6-sol'),
      const Duration(minutes: 10),
    );
    expect(multiAgentRequestAttempts('https://api.example.test/v1'), 4);
    expect(multiAgentMaxParallel('https://api.example.test/v1'), 3);
  });

  test('menjalankan task paralel pada branch dan worktree berbeda', () async {
    final commands = <List<String>>[];
    final running = <String>{};
    var peak = 0;
    final manager = GitWorktreeManager(
      storageRoot: r'C:\temp\younz-worktrees',
      clock: () => DateTime.fromMicrosecondsSinceEpoch(1000),
      processRunner: (executable, arguments, {workingDirectory}) async {
        commands.add(arguments);
        if (arguments.first == 'rev-parse' &&
            arguments.contains('--show-toplevel')) {
          return ProcessResult(1, 0, 'C:/repo', '');
        }
        if (arguments.first == 'rev-parse' && arguments.contains('HEAD')) {
          return ProcessResult(1, 0, 'abc123', '');
        }
        return ProcessResult(1, 0, '', '');
      },
    );
    final changes = <AgentTask>[];
    final orchestrator = MultiAgentOrchestrator(
      workspace: r'C:\repo',
      worktreeManager: manager,
      maxParallel: 2,
      onTaskChanged: changes.add,
      runner: (task, worktree) async {
        running.add(task.id);
        peak = running.length > peak ? running.length : peak;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        running.remove(task.id);
        return 'done ${task.prompt}';
      },
    );

    final tasks = await orchestrator.run(['buat API', 'buat UI', 'buat tes']);

    expect(tasks, hasLength(3));
    expect(
      tasks.every((task) => task.status == AgentTaskStatus.completed),
      true,
    );
    expect(tasks.map((task) => task.branch).toSet(), hasLength(3));
    expect(tasks.map((task) => task.worktree).toSet(), hasLength(3));
    expect(tasks.map((task) => task.nodeId), ['agent-0', 'agent-1', 'agent-2']);
    for (final nodeId in tasks.map((task) => task.nodeId)) {
      expect(
        changes
            .where((task) => task.nodeId == nodeId)
            .map((task) => task.nodeId),
        everyElement(nodeId),
      );
    }
    expect(peak, 2);
    expect(
      commands.where((command) => command.take(2).join(' ') == 'worktree add'),
      hasLength(3),
    );
    expect(
      changes.any((task) => task.status == AgentTaskStatus.running),
      isTrue,
    );
  });

  test('menolak repository tanpa commit sebelum membuat worktree', () async {
    final commands = <List<String>>[];
    final manager = GitWorktreeManager(
      storageRoot: r'C:\temp\younz-worktrees',
      processRunner: (executable, arguments, {workingDirectory}) async {
        commands.add(arguments);
        if (arguments.first == 'rev-parse' &&
            arguments.contains('--show-toplevel')) {
          return ProcessResult(1, 0, 'C:/repo', '');
        }
        if (arguments.first == 'rev-parse' && arguments.contains('HEAD')) {
          return ProcessResult(1, 128, '', 'fatal: ambiguous argument HEAD');
        }
        return ProcessResult(1, 0, '', '');
      },
    );

    await expectLater(
      manager.prepare('C:/repo', 'audit aksesibilitas', 0),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('belum memiliki commit'),
        ),
      ),
    );
    expect(commands.any((command) => command.first == 'worktree'), isFalse);
  });

  test(
    'runGraph hanya dispatch runnable dan memblokir descendant gagal',
    () async {
      final manager = GitWorktreeManager(
        storageRoot: r'C:\temp\younz-worktrees',
        processRunner: (executable, arguments, {workingDirectory}) async {
          if (arguments.first == 'rev-parse' &&
              arguments.contains('--show-toplevel')) {
            return ProcessResult(1, 0, 'C:/repo', '');
          }
          if (arguments.first == 'rev-parse' && arguments.contains('HEAD')) {
            return ProcessResult(1, 0, 'abc123', '');
          }
          return ProcessResult(1, 0, '', '');
        },
      );
      final started = <String>[];
      final orchestrator = MultiAgentOrchestrator(
        workspace: r'C:\repo',
        worktreeManager: manager,
        runner: (task, _) async {
          started.add(task.nodeId);
          if (task.nodeId == 'build') throw StateError('boom');
          return 'ok';
        },
      );
      final graph = TaskGraph(
        id: 'dag',
        objective: 'DAG scheduling',
        nodes: const [
          TaskNode(id: 'build', title: 'Build'),
          TaskNode(id: 'test', title: 'Test', dependencies: ['build']),
        ],
      );

      final result = await orchestrator.runGraph(graph);

      expect(started, ['build']);
      expect(result.tasks.single.status, AgentTaskStatus.failed);
      expect(result.graph.node('build').status, TaskNodeStatus.failed);
      expect(result.graph.node('test').status, TaskNodeStatus.blocked);
    },
  );

  test('kegagalan satu task tidak menghentikan task lain', () async {
    final manager = GitWorktreeManager(
      storageRoot: r'C:\temp\younz-worktrees',
      processRunner: (executable, arguments, {workingDirectory}) async {
        if (arguments.first == 'rev-parse' &&
            arguments.contains('--show-toplevel')) {
          return ProcessResult(1, 0, 'C:/repo', '');
        }
        if (arguments.first == 'rev-parse' && arguments.contains('HEAD')) {
          return ProcessResult(1, 0, 'abc123', '');
        }
        return ProcessResult(1, 0, '', '');
      },
    );
    final orchestrator = MultiAgentOrchestrator(
      workspace: r'C:\repo',
      worktreeManager: manager,
      runner: (task, _) async {
        if (task.prompt == 'gagal') throw StateError('boom');
        return 'ok';
      },
    );

    final tasks = await orchestrator.run(['gagal', 'berhasil']);

    expect(tasks.first.status, AgentTaskStatus.failed);
    expect(tasks.last.status, AgentTaskStatus.completed);
  });

  test('hasil 12001+ utuh untuk chat tetapi aman di graph', () async {
    final longResult = 'token=super-secret\n${'x' * 12001}';
    final result =
        await MultiAgentOrchestrator(
          workspace: 'C:/repo',
          worktreeManager: _manager((_) => ''),
          runner: (_, _) async => longResult,
        ).runGraph(
          TaskGraph(
            id: 'large',
            objective: 'Large',
            nodes: const [TaskNode(id: 'task', title: 'Task')],
          ),
        );
    expect(result.tasks.single.result, longResult);
    expect(result.graph.node('task').status, TaskNodeStatus.completed);
    expect(result.graph.node('task').detail.length, lessThanOrEqualTo(12000));
    expect(result.graph.node('task').detail, isNot(contains('super-secret')));
  });

  test('error 12001+ utuh untuk chat tetapi aman di graph', () async {
    final longError = 'api_key=super-secret\n${'e' * 12001}';
    final result =
        await MultiAgentOrchestrator(
          workspace: 'C:/repo',
          worktreeManager: _manager((_) => ''),
          runner: (_, _) async => throw StateError(longError),
        ).runGraph(
          TaskGraph(
            id: 'large-error',
            objective: 'Large error',
            nodes: const [TaskNode(id: 'task', title: 'Task')],
          ),
        );
    expect(result.tasks.single.error, contains(longError));
    expect(result.graph.node('task').status, TaskNodeStatus.failed);
    expect(result.graph.node('task').detail.length, lessThanOrEqualTo(12000));
    expect(result.graph.node('task').detail, isNot(contains('super-secret')));
  });

  test('exception callback observability tidak menggagalkan task', () async {
    final tasks = await MultiAgentOrchestrator(
      workspace: 'C:/repo',
      worktreeManager: _manager((_) => ''),
      onTaskChanged: (_) => throw StateError('UI disposed'),
      runner: (_, _) async => 'chat result',
    ).run(['task']);
    expect(tasks.single.status, AgentTaskStatus.completed);
    expect(tasks.single.result, 'chat result');
  });

  test('worktree gagal clean dihapus tanpa force', () async {
    final commands = <List<String>>[];
    final task = (await MultiAgentOrchestrator(
      workspace: 'C:/repo',
      worktreeManager: _manager((args) {
        commands.add(args);
        return '';
      }),
      runner: (_, _) async => throw StateError('boom'),
    ).run(['task'])).single;
    expect(task.worktreeStatus, AgentWorktreeStatus.removedCleanFailure);
    expect(
      commands.any(
        (command) =>
            command.join(' ') == 'status --porcelain --untracked-files=all',
      ),
      isTrue,
    );
    expect(
      commands.any(
        (c) =>
            c.take(2).join(' ') == 'worktree remove' && !c.contains('--force'),
      ),
      isTrue,
    );
  });

  test('worktree dirty gagal dan sukses dipertahankan', () async {
    final commands = <List<String>>[];
    final tasks = await MultiAgentOrchestrator(
      workspace: 'C:/repo',
      worktreeManager: _manager((args) {
        commands.add(args);
        return args.first == 'status' ? ' M lib/a.dart\n' : '';
      }),
      runner: (task, _) async {
        if (task.prompt == 'dirty') throw StateError('boom');
        return 'done';
      },
    ).run(['dirty', 'success']);
    expect(tasks.first.worktreeStatus, AgentWorktreeStatus.retainedDirty);
    expect(tasks.last.worktreeStatus, AgentWorktreeStatus.retainedSuccess);
    expect(
      commands.any((c) => c.take(2).join(' ') == 'worktree remove'),
      isFalse,
    );
  });
}

GitWorktreeManager _manager(String Function(List<String>) output) =>
    GitWorktreeManager(
      storageRoot: r'C:\temp\younz-worktrees',
      processRunner: (executable, arguments, {workingDirectory}) async {
        if (arguments.contains('--show-toplevel')) {
          return ProcessResult(1, 0, 'C:/repo', '');
        }
        if (arguments.contains('HEAD')) {
          return ProcessResult(1, 0, 'abc123', '');
        }
        return ProcessResult(1, 0, output(arguments), '');
      },
    );
