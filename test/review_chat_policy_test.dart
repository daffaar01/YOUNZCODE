import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('review success masuk chat dan modal hanya dipakai saat apply', () {
    final source = File('lib/app/command_workflow.dart').readAsStringSync();
    final reviewStart = source.indexOf('Future<void> _openReview()');
    final applyStart = source.indexOf('Future<void> _applyReviewFinding(');
    final nextStart = source.indexOf('String _reviewMessageText(', applyStart);

    expect(reviewStart, greaterThanOrEqualTo(0));
    expect(applyStart, greaterThan(reviewStart));
    expect(nextStart, greaterThan(applyStart));

    final reviewBody = source.substring(reviewStart, applyStart);
    final applyBody = source.substring(applyStart, nextStart);
    expect(reviewBody, contains('_addLocalResponse('));
    expect(reviewBody, contains('formatReviewForChat('));
    expect(reviewBody, isNot(contains('showDialog<int>(')));
    expect(applyBody, contains('showDialog<int>('));
    expect(applyBody, contains('_gitService.checkPatch'));
    expect(applyBody, contains('_trustCurrentWorkspace()'));
    expect(applyBody, contains('_reviewApplyWorkspaceIsSafe()'));
    expect(applyBody, contains('canApplyReviewFinding('));
  });
}
