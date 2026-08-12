import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('review success masuk chat tanpa state-changing apply path', () {
    final workflow = File('lib/app/command_workflow.dart').readAsStringSync();
    final mainSource = File('lib/main.dart').readAsStringSync();
    final reviewStart = workflow.indexOf('Future<void> _openReview()');
    final nextStart = workflow.indexOf(
      'String _reviewMessageText(',
      reviewStart,
    );

    expect(reviewStart, greaterThanOrEqualTo(0));
    expect(nextStart, greaterThan(reviewStart));

    final reviewBody = workflow.substring(reviewStart, nextStart);
    expect(reviewBody, contains('_addLocalResponse('));
    expect(reviewBody, contains('formatReviewForChat('));
    expect(reviewBody, isNot(contains('showDialog<int>(')));
    expect(reviewBody, isNot(contains('applyPatch(')));
    expect(reviewBody, isNot(contains('applyValidatedPatch(')));
    expect(workflow, isNot(contains('_applyReviewFinding(')));
    expect(workflow, isNot(contains('/review-apply')));
    expect(mainSource, isNot(contains('/review-apply')));
  });
}
