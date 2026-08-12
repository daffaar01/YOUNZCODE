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

  test('newest user request dipertahankan dan dipotong deterministik', () {
    final newest = 'NEWEST-REQUEST-${'z' * 200}';
    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': 'system instruction'},
      {'role': 'user', 'content': 'old request'},
      {'role': 'assistant', 'content': 'old response'},
      {'role': 'user', 'content': newest},
    ];

    final bounded = PromptBudget.constrainMessages(
      messages,
      maxCharacters: 100,
    );

    expect(PromptBudget.messageCharacters(bounded), lessThanOrEqualTo(100));
    expect(bounded.last['role'], 'user');
    expect(bounded.last['content'], isNotEmpty);
    expect(newest, startsWith(bounded.last['content'] as String));
    expect(
      bounded.any((message) => message['content'] == 'old request'),
      isFalse,
    );
  });

  test('combined request cap menghitung system addon history dan prompt', () {
    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': 's' * 12},
      {'role': 'user', 'content': 'old-secret-${'h' * 12}'},
      {'role': 'assistant', 'content': 'a' * 12},
      {'role': 'user', 'content': 'attachment-${'x' * 20}'},
    ];

    final bounded = PromptBudget.constrainMessages(
      messages,
      maxCharacters: 120,
    );

    expect(PromptBudget.messageCharacters(bounded), lessThanOrEqualTo(120));
    expect(bounded.first['role'], 'system');
    expect(bounded.last['content'], contains('attachment-'));
    expect(
      bounded.any((message) => '${message['content']}'.contains('old-secret-')),
      isFalse,
    );
  });
}
