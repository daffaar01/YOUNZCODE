import 'package:flutter_test/flutter_test.dart';
import 'package:kode_agent_desktop/services/prompt_budget.dart';

void main() {
  test('user prompt sendiri tidak dapat melewati hard cap', () {
    final budget = PromptBudget(maxCharacters: 20);

    budget.writeInitial('x' * 30);

    expect(budget.toString().length, 20);
  });

  test('attachment header content dan marker bersama-sama tetap bounded', () {
    final budget = PromptBudget(maxCharacters: 64)..writeInitial('prompt');

    budget.appendBlock(
      header: '\n\n--- large.txt (text) ---\n',
      content: 'a' * 100,
      truncationMarker: '\n[TRUNCATED]',
    );

    expect(budget.toString().length, lessThanOrEqualTo(64));
    expect(budget.toString(), contains('--- large.txt'));
    expect(budget.toString(), endsWith('[TRUNCATED]'));
  });
}
