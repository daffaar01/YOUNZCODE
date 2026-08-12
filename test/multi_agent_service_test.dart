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
}
