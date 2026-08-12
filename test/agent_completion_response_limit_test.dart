import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:kode_agent_desktop/services/agent_completion_client.dart';

void main() {
  test(
    'completion tool-free memakai respons utuh pada 9Router lokal',
    () async {
      final transport = _RecordingClient();
      final client = AgentCompletionClient(
        baseUrl: 'http://127.0.0.1:20128/v1',
        apiKey: 'test-key',
        model: 'cx/gpt-5.6-sol(max)',
        timeoutMs: 5000,
        headers: const {},
        maxRequestAttempts: 1,
        retryBaseDelay: Duration.zero,
        onStatus: (_) {},
        isCancelled: () => false,
        shouldStop: () => false,
        httpClient: transport,
      );

      final result = await client.request(
        messages: const [
          {'role': 'user', 'content': 'review'},
        ],
        toolDefinitions: const [],
        allowTools: false,
      );

      expect(transport.requestBody['stream'], isFalse);
      expect(result['content'], 'OK');
    },
  );

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

class _RecordingClient extends http.BaseClient {
  Map<String, dynamic> requestBody = const {};

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = await request.finalize().transform(utf8.decoder).join();
    requestBody = Map<String, dynamic>.from(jsonDecode(body) as Map);
    final response = requestBody['stream'] == true
        ? 'data: {"choices":[{"delta":{"role":"assistant","content":"OK"},"finish_reason":"stop"}]}\n\ndata: [DONE]\n\n'
        : '{"choices":[{"message":{"role":"assistant","content":"OK"}}]}';
    return http.StreamedResponse(
      Stream.value(utf8.encode(response)),
      200,
      headers: {
        'content-type': requestBody['stream'] == true
            ? 'text/event-stream'
            : 'application/json',
      },
    );
  }
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
