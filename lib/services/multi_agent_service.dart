import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import '../models/task_graph.dart';
import 'secret_scanner.dart';

String taskGraphSafeDetail(String value) {
  final redacted = SecretScanner.redact(value);
  return redacted.length <= 12000 ? redacted : redacted.substring(0, 12000);
}

int multiAgentRequestTimeoutMs({
  required String model,
  required int configuredTimeoutMs,
}) {
  if (model.trim().toLowerCase().endsWith('(max)')) {
    return configuredTimeoutMs < 600000 ? 600000 : configuredTimeoutMs;
  }
  return configuredTimeoutMs;
}

Duration multiAgentTurnDuration(String model) =>
    model.trim().toLowerCase().endsWith('(max)')
    ? const Duration(minutes: 30)
    : const Duration(minutes: 10);

bool _isLocalMultiAgentProvider(String baseUrl) {
  final uri = Uri.tryParse(baseUrl.trim());
  final host = uri?.host.toLowerCase();
  return host == '127.0.0.1' || host == 'localhost';
}

int multiAgentRequestAttempts(String baseUrl) =>
    _isLocalMultiAgentProvider(baseUrl) ? 1 : 4;

int multiAgentMaxParallel(String baseUrl) =>
    _isLocalMultiAgentProvider(baseUrl) ? 1 : 3;

String formatMultiAgentResultsForChat(
  List<AgentTask> tasks, {
  int maxDetailCharacters = 4000,
}) {
  final completed = tasks
      .where((task) => task.status == AgentTaskStatus.completed)
      .length;
  final buffer = StringBuffer(
    'MULTI-AGENT RESULTS — $completed/${tasks.length} selesai',
  );
  for (var index = 0; index < tasks.length; index++) {
    final task = tasks[index];
    final icon = switch (task.status) {
      AgentTaskStatus.completed => '✅',
      AgentTaskStatus.failed => '❌',
      AgentTaskStatus.cancelled => '⏹️',
      _ => '⏳',
    };
    final rawDetail = task.error.isNotEmpty ? task.error : task.result;
    final detail = rawDetail.length <= maxDetailCharacters
        ? rawDetail
        : '${rawDetail.substring(0, maxDetailCharacters)}…';
    buffer
      ..writeln()
      ..writeln()
      ..writeln('${index + 1}. $icon ${task.prompt}');
    if (task.branch.isNotEmpty) {
      buffer.writeln('Branch: ${task.branch}');
    }
    if (detail.trim().isNotEmpty) {
      buffer.write(detail.trim());
    } else {
      buffer.write('Tidak ada detail hasil.');
    }
  }
  return buffer.toString();
}

enum AgentTaskStatus {
  queued,
  preparing,
  running,
  completed,
  failed,
  cancelled,
}

enum AgentWorktreeStatus {
  none,
  retainedSuccess,
  retainedDirty,
  retainedCleanupFailed,
  removedCleanFailure,
}

class AgentTask {
  const AgentTask({
    required this.id,
    required this.nodeId,
    required this.prompt,
    this.status = AgentTaskStatus.queued,
    this.branch = '',
    this.worktree = '',
    this.result = '',
    this.error = '',
    this.worktreeStatus = AgentWorktreeStatus.none,
    this.startedAt,
    this.finishedAt,
  });

  final String id;
  final String nodeId;
  final String prompt;
  final AgentTaskStatus status;
  final String branch;
  final String worktree;
  final String result;
  final String error;
  final AgentWorktreeStatus worktreeStatus;
  final DateTime? startedAt;
  final DateTime? finishedAt;

  AgentTask copyWith({
    AgentTaskStatus? status,
    String? branch,
    String? worktree,
    String? result,
    String? error,
    AgentWorktreeStatus? worktreeStatus,
    DateTime? startedAt,
    DateTime? finishedAt,
  }) => AgentTask(
    id: id,
    nodeId: nodeId,
    prompt: prompt,
    status: status ?? this.status,
    branch: branch ?? this.branch,
    worktree: worktree ?? this.worktree,
    result: result ?? this.result,
    error: error ?? this.error,
    worktreeStatus: worktreeStatus ?? this.worktreeStatus,
    startedAt: startedAt ?? this.startedAt,
    finishedAt: finishedAt ?? this.finishedAt,
  );
}

typedef GitProcessRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
    });

class GitWorktreeManager {
  GitWorktreeManager({
    String? storageRoot,
    GitProcessRunner? processRunner,
    DateTime Function()? clock,
  }) : _storageRoot =
           storageRoot ??
           path.join(Directory.systemTemp.path, 'YOUNZCODE', 'worktrees'),
       _processRunner = processRunner ?? _runProcess,
       _clock = clock ?? DateTime.now;

  final String _storageRoot;
  final GitProcessRunner _processRunner;
  final DateTime Function() _clock;

  Future<({String branch, String worktree})> prepare(
    String workspace,
    String prompt,
    int index,
  ) async {
    final rootResult = await _git(workspace, ['rev-parse', '--show-toplevel']);
    final repositoryRoot = '${rootResult.stdout}'.trim();
    if (repositoryRoot.isEmpty) {
      throw StateError('Workspace bukan repository Git.');
    }
    final headResult = await _processRunner('git', [
      'rev-parse',
      '--verify',
      'HEAD',
    ], workingDirectory: repositoryRoot);
    if (headResult.exitCode != 0 || '${headResult.stdout}'.trim().isEmpty) {
      throw StateError(
        'Repository belum memiliki commit. Commit file yang akan diperiksa '
        'sebelum menjalankan /agents; file untracked tidak dapat disalin ke '
        'worktree agent.',
      );
    }
    final stamp = _clock().microsecondsSinceEpoch;
    final slug = _slug(prompt);
    final branch = 'codex/agent-$slug-$stamp-$index';
    final repositoryId = _stableHash(path.normalize(repositoryRoot));
    final worktree = path.join(_storageRoot, repositoryId, '$stamp-$index');
    await Directory(path.dirname(worktree)).create(recursive: true);
    await _git(repositoryRoot, [
      'worktree',
      'add',
      '-b',
      branch,
      worktree,
      'HEAD',
    ]);
    return (branch: branch, worktree: worktree);
  }

  Future<void> remove(String workspace, String worktree) async {
    final resolvedWorkspace = path.normalize(path.absolute(workspace));
    final resolvedWorktree = path.normalize(path.absolute(worktree));
    final resolvedStorage = path.normalize(path.absolute(_storageRoot));
    if (!path.isWithin(resolvedStorage, resolvedWorktree) ||
        resolvedWorktree == resolvedWorkspace) {
      throw StateError('Worktree berada di luar storage YOUNZCODE.');
    }
    await _git(workspace, ['worktree', 'remove', resolvedWorktree]);
    await _git(workspace, ['worktree', 'prune']);
  }

  Future<bool> isClean(String worktree) async {
    final result = await _git(worktree, [
      'status',
      '--porcelain',
      '--untracked-files=all',
    ]);
    return '${result.stdout}'.trim().isEmpty;
  }

  Future<ProcessResult> _git(
    String workingDirectory,
    List<String> arguments,
  ) async {
    final result = await _processRunner(
      'git',
      arguments,
      workingDirectory: workingDirectory,
    );
    if (result.exitCode != 0) {
      throw ProcessException(
        'git',
        arguments,
        '${result.stderr}'.trim(),
        result.exitCode,
      );
    }
    return result;
  }

  static Future<ProcessResult> _runProcess(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) => Process.run(executable, arguments, workingDirectory: workingDirectory);

  static String _slug(String prompt) {
    final value = prompt
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (value.isEmpty) return 'task';
    return value.substring(0, value.length.clamp(1, 28));
  }

  static String _stableHash(String value) {
    var hash = 0xcbf29ce484222325;
    for (final byte in utf8.encode(value.toLowerCase())) {
      hash ^= byte;
      hash = (hash * 0x100000001b3) & 0x7fffffffffffffff;
    }
    return hash.toRadixString(16);
  }
}

typedef IsolatedAgentRunner =
    Future<String> Function(AgentTask task, String worktree);
typedef AgentTaskChanged = void Function(AgentTask task);

class MultiAgentOrchestrator {
  MultiAgentOrchestrator({
    required this.workspace,
    required this.runner,
    GitWorktreeManager? worktreeManager,
    this.maxParallel = 3,
    this.onTaskChanged,
  }) : worktreeManager = worktreeManager ?? GitWorktreeManager();

  final String workspace;
  final IsolatedAgentRunner runner;
  final GitWorktreeManager worktreeManager;
  final int maxParallel;
  final AgentTaskChanged? onTaskChanged;

  Future<List<AgentTask>> run(List<String> prompts) async {
    if (prompts.isEmpty) return const [];
    final tasks = [
      for (var index = 0; index < prompts.length; index++)
        AgentTask(
          id: '${DateTime.now().microsecondsSinceEpoch}-$index',
          nodeId: 'agent-$index',
          prompt: prompts[index].trim(),
        ),
    ];
    return _runTasks(tasks);
  }

  Future<({TaskGraph graph, List<AgentTask> tasks})> runGraph(
    TaskGraph initial,
  ) async {
    var graph = initial;
    final completedTasks = <AgentTask>[];
    while (graph.runnable.isNotEmpty) {
      final runnable = graph.runnable;
      final tasks = [
        for (var index = 0; index < runnable.length; index++)
          AgentTask(
            id: '${DateTime.now().microsecondsSinceEpoch}-$index',
            nodeId: runnable[index].id,
            prompt: runnable[index].title,
          ),
      ];
      final results = await _runTasks(tasks);
      for (final task in results) {
        final worktreeSegments = task.worktree
            .replaceAll('\\', '/')
            .split('/')
            .where((segment) => segment.isNotEmpty)
            .toList();
        final worktreeAlias = worktreeSegments.isEmpty
            ? ''
            : worktreeSegments.last;
        graph = graph.transition(
          task.nodeId,
          TaskNodeStatus.running,
          agentId: task.id,
          worktree: worktreeAlias,
        );
        final terminal = switch (task.status) {
          AgentTaskStatus.completed => TaskNodeStatus.completed,
          AgentTaskStatus.failed => TaskNodeStatus.failed,
          AgentTaskStatus.cancelled => TaskNodeStatus.cancelled,
          _ => throw StateError(
            'Agent task berhenti pada status non-terminal.',
          ),
        };
        graph = graph.transition(
          task.nodeId,
          terminal,
          detail: taskGraphSafeDetail(
            task.error.isEmpty ? task.result : task.error,
          ),
          agentId: task.id,
          worktree: worktreeAlias,
        );
      }
      completedTasks.addAll(results);
    }
    return (graph: graph, tasks: List<AgentTask>.unmodifiable(completedTasks));
  }

  Future<List<AgentTask>> _runTasks(List<AgentTask> tasks) async {
    var cursor = 0;
    Future<void> worker() async {
      while (cursor < tasks.length) {
        final index = cursor++;
        tasks[index] = await _runTask(tasks[index], index);
      }
    }

    final workers = maxParallel.clamp(1, tasks.length);
    await Future.wait([for (var index = 0; index < workers; index++) worker()]);
    return List.unmodifiable(tasks);
  }

  Future<AgentTask> _runTask(AgentTask task, int index) async {
    var current = task.copyWith(
      status: AgentTaskStatus.preparing,
      startedAt: DateTime.now(),
    );
    _notify(current);
    try {
      final prepared = await worktreeManager.prepare(
        workspace,
        task.prompt,
        index,
      );
      current = current.copyWith(
        status: AgentTaskStatus.running,
        branch: prepared.branch,
        worktree: prepared.worktree,
      );
      _notify(current);
      final result = await runner(current, prepared.worktree);
      current = current.copyWith(
        status: AgentTaskStatus.completed,
        result: result,
        finishedAt: DateTime.now(),
      );
    } catch (error) {
      current = current.copyWith(
        status: AgentTaskStatus.failed,
        error: '$error',
        finishedAt: DateTime.now(),
      );
    }
    current = await _applyWorktreePolicy(current);
    _notify(current);
    return current;
  }

  void _notify(AgentTask task) {
    try {
      onTaskChanged?.call(task);
    } catch (_) {
      // Observability must never change orchestration outcome.
    }
  }

  Future<AgentTask> _applyWorktreePolicy(AgentTask task) async {
    if (task.worktree.isEmpty) return task;
    if (task.status == AgentTaskStatus.completed) {
      return task.copyWith(worktreeStatus: AgentWorktreeStatus.retainedSuccess);
    }
    if (task.status != AgentTaskStatus.failed &&
        task.status != AgentTaskStatus.cancelled) {
      return task;
    }
    try {
      if (!await worktreeManager.isClean(task.worktree)) {
        return task.copyWith(worktreeStatus: AgentWorktreeStatus.retainedDirty);
      }
      await worktreeManager.remove(workspace, task.worktree);
      return task.copyWith(
        worktreeStatus: AgentWorktreeStatus.removedCleanFailure,
      );
    } catch (_) {
      return task.copyWith(
        worktreeStatus: AgentWorktreeStatus.retainedCleanupFailed,
      );
    }
  }
}
