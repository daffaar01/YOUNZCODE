import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kode_agent_desktop/main.dart';
import 'package:kode_agent_desktop/models/task_graph.dart';

void main() {
  testWidgets('task graph banner menampilkan status dan artifact node', (
    tester,
  ) async {
    final graph =
        TaskGraph(
              id: 'agents',
              objective: 'Parallel review',
              nodes: const [
                TaskNode(id: 'review', title: 'Security review'),
                TaskNode(
                  id: 'test',
                  title: 'Run tests',
                  dependencies: ['review'],
                ),
              ],
            )
            .transition('review', TaskNodeStatus.running)
            .transition(
              'review',
              TaskNodeStatus.completed,
              artifacts: const [
                TaskArtifact(
                  kind: 'branch',
                  label: 'Git branch',
                  value: 'agent/review',
                ),
              ],
            );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TaskGraphBanner(graph: graph)),
      ),
    );

    expect(find.byKey(const ValueKey('task-graph-banner')), findsOneWidget);
    expect(find.text('Parallel review'), findsOneWidget);
    expect(find.text('COMPLETED · TRY 1'), findsOneWidget);
    expect(find.text('PENDING · TRY 1'), findsOneWidget);
    expect(find.byKey(const ValueKey('task-edge-review-test')), findsOneWidget);

    await tester.longPress(find.byKey(const ValueKey('task-node-review')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Artifacts: Git branch'), findsOneWidget);
  });
}
