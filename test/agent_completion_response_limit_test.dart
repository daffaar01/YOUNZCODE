import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:kode_agent_desktop/services/agent_completion_client.dart';

void main() {
  test(
    'completion menghentikan stream ketika byte budget terlampaui',
    () async {
      final client = AgentCompletionClient(
        baseUrl: 'https://api.openai.com/v1',
        apiKey: '',
        model: 'test-model',
        timeoutMs: 5000,
        headers: const {},
        maxRequestAttempts: 1,
        retryBaseDelay: Duration.zero,
        onStatus: (_) {},
        isCancelled: () => false,
        shouldStop: () => false,
        maxResponseBytes: 1024,
        httpClient: _ChunkedClient(),
      );

      await expectLater(
        client.request(
          messages: const [
            {'role': 'user', 'content': 'review'},
          ],
          toolDefinitions: const [],
          allowTools: false,
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('response byte limit'),
          ),
        ),
      );
    },
  );
}

class _ChunkedClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      Stream<List<int>>.fromIterable([
        utf8.encode('x' * 800),
        utf8.encode('y' * 800),
      ]),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
}
