import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ordinary workspace search guards result error dan cleanup', () {
    final source = File('lib/app/workspace_lifecycle.dart').readAsStringSync();
    final start = source.indexOf('Future<void> _searchWorkspace()');
    final section = source.substring(start);

    expect(start, greaterThanOrEqualTo(0));
    expect(section, contains('final guard = WorkspaceSearchGuard('));
    expect(
      RegExp(r'guard\.isCurrent\(').allMatches(section),
      hasLength(greaterThanOrEqualTo(3)),
    );
    expect(section, isNot(contains('searchedWorkspace != _workspace')));
  });
}
