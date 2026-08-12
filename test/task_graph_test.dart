import 'package:flutter_test/flutter_test.dart';
import 'package:kode_agent_desktop/models/task_graph.dart';

void main() {
  TaskGraph graph() => TaskGraph(
    id: 'release',
    objective: 'Kirim release aman',
    nodes: const [
      TaskNode(id: 'implement', title: 'Implementasi'),
      TaskNode(id: 'test', title: 'Test', dependencies: ['implement']),
      TaskNode(id: 'review', title: 'Review', dependencies: ['implement']),
      TaskNode(
        id: 'release',
        title: 'Release',
        dependencies: ['test', 'review'],
      ),
    ],
  );

  test('DAG menolak dependency yang hilang dan cycle', () {
    expect(
      () => TaskGraph(
        id: 'missing',
        objective: 'invalid',
        nodes: const [
          TaskNode(id: 'a', title: 'A', dependencies: ['b']),
        ],
      ),
      throwsFormatException,
    );
    expect(
      () => TaskGraph(
        id: 'cycle',
        objective: 'invalid',
        nodes: const [
          TaskNode(id: 'a', title: 'A', dependencies: ['b']),
          TaskNode(id: 'b', title: 'B', dependencies: ['a']),
        ],
      ),
      throwsFormatException,
    );
  });

  test('hanya node dengan dependency selesai yang runnable', () {
    var value = graph();
    expect(value.runnable.map((node) => node.id), ['implement']);

    value = value.transition('implement', TaskNodeStatus.running);
    value = value.transition('implement', TaskNodeStatus.completed);

    expect(value.runnable.map((node) => node.id), ['test', 'review']);
  });

  test('state machine menolak transisi ilegal', () {
    final value = graph();
    expect(
      () => value.transition('test', TaskNodeStatus.running),
      throwsStateError,
    );
    expect(
      () => value.transition('implement', TaskNodeStatus.completed),
      throwsStateError,
    );
  });

  test('pause resume retry dan cancel mengikuti state machine', () {
    var value = graph().transition('implement', TaskNodeStatus.running);
    value = value.transition('implement', TaskNodeStatus.paused);
    value = value.transition('implement', TaskNodeStatus.running);
    value = value.transition(
      'implement',
      TaskNodeStatus.failed,
      detail: 'test gagal',
    );
    value = value.retry('implement');
    expect(value.node('implement').status, TaskNodeStatus.pending);
    expect(value.node('implement').attempt, 2);

    value = value.transition('implement', TaskNodeStatus.running);
    value = value.transition('implement', TaskNodeStatus.cancelled);
    expect(value.node('implement').status, TaskNodeStatus.cancelled);
  });

  test('JSON roundtrip mempertahankan graph dan artifacts', () {
    var value = graph().transition('implement', TaskNodeStatus.running);
    value = value.transition(
      'implement',
      TaskNodeStatus.completed,
      detail: 'selesai',
      artifacts: const [
        TaskArtifact(kind: 'diff', label: 'Perubahan', value: 'change.patch'),
      ],
    );

    final restored = TaskGraph.fromJson(value.toJson());

    expect(restored.toJson(), value.toJson());
    expect(restored.node('implement').artifacts.single.kind, 'diff');
  });

  test('collections node di-copy defensif setelah validasi', () {
    final dependencies = <String>[];
    final artifacts = <TaskArtifact>[];
    final value = TaskGraph(
      id: 'immutable',
      objective: 'Snapshot immutable',
      nodes: [
        TaskNode(
          id: 'a',
          title: 'A',
          dependencies: dependencies,
          artifacts: artifacts,
        ),
      ],
    );

    dependencies.add('missing');
    artifacts.add(
      const TaskArtifact(kind: 'log', label: 'Log', value: 'mutated'),
    );

    expect(value.node('a').dependencies, isEmpty);
    expect(value.node('a').artifacts, isEmpty);
    expect(
      () => value.node('a').dependencies.add('missing'),
      throwsUnsupportedError,
    );
  });

  test('graph menolak dependency duplikat dan lifecycle JSON invalid', () {
    expect(
      () => TaskGraph(
        id: 'duplicate-dependency',
        objective: 'invalid',
        nodes: const [
          TaskNode(id: 'a', title: 'A'),
          TaskNode(id: 'b', title: 'B', dependencies: ['a', 'a']),
        ],
      ),
      throwsFormatException,
    );
    final invalid = graph().toJson();
    final nodes = invalid['nodes']! as List<dynamic>;
    (nodes.first as Map<String, dynamic>)
      ..['status'] = TaskNodeStatus.completed.name
      ..['attempt'] = 0;
    expect(() => TaskGraph.fromJson(invalid), throwsFormatException);
  });

  test('graph membatasi node, artifact, dan field string', () {
    expect(
      () => TaskGraph(
        id: 'oversize',
        objective: 'invalid',
        nodes: [
          for (var index = 0; index < 65; index++)
            TaskNode(id: 'n$index', title: 'Node $index'),
        ],
      ),
      throwsFormatException,
    );
    expect(
      () => TaskGraph(
        id: 'artifacts',
        objective: 'invalid',
        nodes: [
          TaskNode(
            id: 'a',
            title: 'A',
            artifacts: [
              for (var index = 0; index < 33; index++)
                TaskArtifact(kind: 'log', label: '$index', value: 'value'),
            ],
          ),
        ],
      ),
      throwsFormatException,
    );
    expect(
      () => TaskGraph(
        id: 'long',
        objective: 'x' * 12001,
        nodes: const [TaskNode(id: 'a', title: 'A')],
      ),
      throwsFormatException,
    );
  });

  test('dependency gagal memblokir seluruh dependent transitif', () {
    var value = graph().transition('implement', TaskNodeStatus.running);
    value = value.transition('implement', TaskNodeStatus.failed);

    expect(value.node('test').status, TaskNodeStatus.blocked);
    expect(value.node('review').status, TaskNodeStatus.blocked);
    expect(value.node('release').status, TaskNodeStatus.blocked);
  });

  test('restore mengubah running menjadi paused agar tidak auto-resume', () {
    var value = graph().transition('implement', TaskNodeStatus.running);

    value = TaskGraph.fromJson(value.toJson(), safeRestore: true);

    expect(value.node('implement').status, TaskNodeStatus.paused);
    expect(value.node('implement').detail, contains('dipulihkan'));
  });
}
