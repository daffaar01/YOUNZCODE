import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'declarative command mempertahankan composer sampai preflight selesai',
    () {
      final source = File('lib/app/command_workflow.dart').readAsStringSync();
      final start = source.indexOf('Future<void> _runDeclarativeCommand(');
      final end = source.indexOf('\n  Future<void> _runMultiAgents(', start);
      final method = source.substring(start, end);

      final confirmation = method.indexOf('await _confirmMainBranchWork()');
      final clear = method.indexOf('_promptController.clear()');
      final operation = method.indexOf('await _runAgentOperation(');

      expect(confirmation, greaterThanOrEqualTo(0));
      expect(clear, greaterThan(confirmation));
      expect(clear, lessThan(operation));
    },
  );
}
