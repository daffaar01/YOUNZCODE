import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('hasil multi-agent masuk chat tanpa membuka results dialog', () {
    final source = File('lib/app/command_workflow.dart').readAsStringSync();
    final start = source.indexOf('Future<void> _runMultiAgents(');
    final end = source.indexOf('Future<void> _openUsageDashboard(', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final body = source.substring(start, end);

    expect(body, contains('_addLocalResponse('));
    expect(body, contains('formatMultiAgentResultsForChat(tasks)'));
    expect(body, isNot(contains('_MultiAgentResultsDialog')));
  });
}
