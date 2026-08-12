import 'package:flutter_test/flutter_test.dart';
import 'package:kode_agent_desktop/services/workspace_search_guard.dart';

void main() {
  test('search guard menolak hasil dari workspace atau service lama', () {
    final originalService = Object();
    final replacementService = Object();
    final guard = WorkspaceSearchGuard(
      workspace: 'C:/workspace-a',
      service: originalService,
    );

    expect(
      guard.isCurrent(workspace: 'C:/workspace-a', service: originalService),
      isTrue,
    );
    expect(
      guard.isCurrent(workspace: 'C:/workspace-b', service: originalService),
      isFalse,
    );
    expect(
      guard.isCurrent(workspace: 'C:/workspace-a', service: replacementService),
      isFalse,
    );
  });
}
