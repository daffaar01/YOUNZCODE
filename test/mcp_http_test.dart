import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kode_agent_desktop/models/addon.dart';
import 'package:kode_agent_desktop/services/mcp_client.dart';

MockClient _server({bool sseToolCall = false}) {
  return MockClient((request) async {
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    final method = body['method'];
    final id = body['id'];
    if (method == 'notifications/initialized') {
      return http.Response('', 202); // notification, no id
    }
    Map<String, dynamic> result;
    switch (method) {
      case 'initialize':
        result = {
          'protocolVersion': '2025-03-26',
          'serverInfo': {'name': 'test', 'version': '1'},
        };
        return http.Response(
          jsonEncode({'jsonrpc': '2.0', 'id': id, 'result': result}),
          200,
          headers: {
            'content-type': 'application/json',
            'mcp-session-id': 'sess-123',
          },
        );
      case 'tools/list':
        result = {
          'tools': [
            {
              'name': 'echo',
              'description': 'Echo a value',
              'inputSchema': {'type': 'object'},
            },
          ],
        };
        return http.Response(
          jsonEncode({'jsonrpc': '2.0', 'id': id, 'result': result}),
          200,
          headers: {'content-type': 'application/json'},
        );
      case 'tools/call':
        // Session id must be echoed on non-initialize requests.
        expect(request.headers['mcp-session-id'], 'sess-123');
        result = {
          'content': [
            {'type': 'text', 'text': 'halo mcp'},
          ],
        };
        final payload = jsonEncode({
          'jsonrpc': '2.0',
          'id': id,
          'result': result,
        });
        if (sseToolCall) {
          return http.Response(
            'event: message\ndata: $payload\n\n',
            200,
            headers: {'content-type': 'text/event-stream'},
          );
        }
        return http.Response(
          payload,
          200,
          headers: {'content-type': 'application/json'},
        );
      default:
        return http.Response('{}', 400);
    }
  });
}

http.Response _baseProtocolResponse(Map<String, dynamic> body) {
  final method = body['method'];
  final id = body['id'];
  if (method == 'notifications/initialized') return http.Response('', 202);
  return http.Response(
    jsonEncode({
      'jsonrpc': '2.0',
      'id': id,
      'result': method == 'initialize'
          ? {
              'protocolVersion': '2025-03-26',
              'serverInfo': {'name': 'test', 'version': '1'},
            }
          : {
              'tools': [
                {
                  'name': 'echo',
                  'description': 'Echo a value',
                  'inputSchema': {'type': 'object'},
                },
              ],
            },
    }),
    200,
    headers: {'content-type': 'application/json'},
  );
}

McpClient _client(MockClient server) => McpClient(
  const McpServerConfig(
    name: 'remote',
    transport: McpTransport.http,
    url: 'https://mcp.test/rpc',
  ),
  workspace: '.',
  httpClient: server,
);

class _SlowDripClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final controller = StreamController<List<int>>();
    final timer = Timer.periodic(
      const Duration(milliseconds: 5),
      (_) => controller.add(const [32]),
    );
    controller.onCancel = () {
      timer.cancel();
    };
    return http.StreamedResponse(
      controller.stream,
      200,
      headers: {'content-type': 'application/json'},
    );
  }
}

class _PersistentSseClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body =
        jsonDecode((request as http.Request).body) as Map<String, dynamic>;
    final id = body['id'];
    final method = body['method'];
    if (method == 'notifications/initialized') {
      return http.StreamedResponse(const Stream.empty(), 202);
    }
    final result = method == 'initialize'
        ? <String, dynamic>{
            'protocolVersion': '2025-03-26',
            'serverInfo': {'name': 'test', 'version': '1'},
          }
        : <String, dynamic>{'tools': const []};
    final controller = StreamController<List<int>>();
    scheduleMicrotask(() {
      controller.add(
        utf8.encode(
          'event: message\ndata: ${jsonEncode({'jsonrpc': '2.0', 'id': id, 'result': result})}\n\n',
        ),
      );
    });
    return http.StreamedResponse(
      controller.stream,
      200,
      headers: {'content-type': 'text/event-stream'},
    );
  }
}

void main() {
  test('MCP endpoint policy rejects userinfo and private addresses', () async {
    await expectLater(
      validateMcpHttpEndpoint(Uri.parse('https://user:pass@example.test/mcp')),
      throwsStateError,
    );
    await expectLater(
      validateMcpHttpEndpoint(
        Uri.parse('https://public.example/mcp'),
        lookup: (_) async => [InternetAddress('169.254.169.254')],
      ),
      throwsStateError,
    );
  });

  test('MCP connection address is the exact validated public IP', () async {
    final address = await resolveMcpConnectAddress(
      Uri.parse('https://public.example/mcp'),
      lookup: (_) async => [InternetAddress('8.8.8.8')],
    );
    expect(address.address, '8.8.8.8');
    await expectLater(
      resolveMcpConnectAddress(
        Uri.parse('https://public.example/mcp'),
        lookup: (_) async => [InternetAddress('10.0.0.1')],
      ),
      throwsStateError,
    );
  });

  test(
    'pinned MCP transport connects the selected address once without re-resolving',
    () async {
      final listener = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final subscription = listener.listen((socket) {
        socket.write(
          'HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nOK',
        );
        unawaited(socket.flush().whenComplete(socket.destroy));
      });
      addTearDown(() async {
        await subscription.cancel();
        await listener.close();
      });

      var lookups = 0;
      var connects = 0;
      final selected = InternetAddress.loopbackIPv4;
      final client = createPinnedMcpHttpClient(
        (_) async {
          lookups++;
          return [selected];
        },
        connect: (address, port) {
          connects++;
          expect(identical(address, selected), isTrue);
          expect(port, listener.port);
          return Socket.startConnect(address, port);
        },
      );
      addTearDown(client.close);

      final response = await client.get(
        Uri.parse('http://localhost:${listener.port}/mcp'),
      );

      expect(response.body, 'OK');
      expect(lookups, 1);
      expect(connects, 1);
    },
  );

  test(
    'pinned MCP transport preserves TLS hostname and rejects TLS errors',
    () async {
      final listener = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final subscription = listener.listen((_) {});
      addTearDown(() async {
        await subscription.cancel();
        await listener.close();
      });
      final client = createPinnedMcpHttpClient(
        (_) async => [InternetAddress.loopbackIPv4],
        secure: (plain, host) async {
          expect(host, 'localhost');
          plain.destroy();
          throw const HandshakeException('certificate rejected');
        },
      );
      addTearDown(client.close);

      await expectLater(
        client.get(Uri.parse('https://localhost:${listener.port}/mcp')),
        throwsA(anything),
      );
    },
  );

  test('pinned MCP transport cancels a stalled TCP connection', () async {
    final cancelled = Completer<void>();
    final client = createPinnedMcpHttpClient(
      (_) async => [InternetAddress.loopbackIPv4],
      connect: (address, port) async => ConnectionTask.fromSocket<Socket>(
        Completer<Socket>().future,
        cancelled.complete,
      ),
    );
    final request = expectLater(
      client.get(Uri.parse('http://localhost:43123/mcp')),
      throwsA(anything),
    );

    await Future<void>.delayed(Duration.zero);
    client.close();

    await cancelled.future.timeout(const Duration(seconds: 2));
    await request;
  });

  test(
    'pinned MCP transport closes a socket stalled during TLS negotiation',
    () async {
      final listener = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final accepted = Completer<Socket>();
      final subscription = listener.listen((socket) {
        if (!accepted.isCompleted) accepted.complete(socket);
      });
      addTearDown(() async {
        await subscription.cancel();
        await listener.close();
      });

      var lookups = 0;
      final tlsStarted = Completer<void>();
      final client = createPinnedMcpHttpClient(
        (host) async {
          lookups++;
          expect(host, 'localhost');
          return [InternetAddress.loopbackIPv4];
        },
        secure: (plain, host) async {
          expect(host, 'localhost');
          tlsStarted.complete();
          return Completer<SecureSocket>().future;
        },
      );
      final request = expectLater(
        client.get(Uri.parse('https://localhost:${listener.port}/mcp')),
        throwsA(anything),
      );
      final socket = await accepted.future.timeout(const Duration(seconds: 2));
      final peerClosed = socket.drain<void>();
      await tlsStarted.future.timeout(const Duration(seconds: 2));

      client.close();

      await expectLater(
        peerClosed.timeout(const Duration(seconds: 2)),
        completes,
      );
      await request;
      expect(lookups, 1);
    },
  );

  test('MCP remote policy rejects every non-global address class', () async {
    const blocked = [
      '100.64.0.1',
      '192.0.2.1',
      '198.18.0.1',
      '198.51.100.1',
      '203.0.113.1',
      '240.0.0.1',
      '::ffff:127.0.0.1',
      '::ffff:10.0.0.1',
      '::ffff:169.254.169.254',
      '2001:db8::1',
    ];
    for (final value in blocked) {
      await expectLater(
        resolveMcpConnectAddress(
          Uri.parse('https://public.example/mcp'),
          lookup: (_) async => [InternetAddress(value)],
        ),
        throwsStateError,
        reason: value,
      );
    }
  });

  test('MCP HTTP rejects redirects instead of following them', () async {
    final server = MockClient(
      (_) async => http.Response(
        '',
        302,
        headers: {'location': 'http://127.0.0.1/internal'},
      ),
    );
    final client = _client(server);
    addTearDown(client.dispose);
    await expectLater(
      client.initialize(approveLaunch: (_, _) async => true),
      throwsA(isA<StateError>()),
    );
  });

  test('MCP SSE returns before persistent stream closes', () async {
    final client = McpClient(
      const McpServerConfig(
        name: 'remote',
        transport: McpTransport.http,
        url: 'https://mcp.test/rpc',
      ),
      workspace: '.',
      httpClient: _PersistentSseClient(),
      requestTimeout: const Duration(seconds: 2),
    );
    addTearDown(client.dispose);
    await client.initialize(approveLaunch: (_, _) async => true);
    expect(client.status, McpConnectionStatus.ready);
  });

  test(
    'MCP redacts exact opaque resolved credential reflected by server',
    () async {
      const opaque = 'opaque-value-without-token-shape';
      final server = MockClient((_) async => http.Response(opaque, 500));
      final client = McpClient(
        const McpServerConfig(
          name: 'remote',
          transport: McpTransport.http,
          url: 'https://mcp.test/rpc',
          headerReferences: {'X-Credential': 'env:TEST'},
        ),
        workspace: '.',
        httpClient: server,
        resolveCredential: (_) async => opaque,
      );
      addTearDown(client.dispose);
      try {
        await client.initialize(approveLaunch: (_, _) async => true);
        fail('expected failure');
      } catch (error) {
        expect('$error', contains('[REDACTED]'));
        expect('$error', isNot(contains(opaque)));
      }
    },
  );

  test('MCP HTTP initialize + tools/list + tools/call (JSON)', () async {
    final client = _client(_server());
    addTearDown(client.dispose);

    var approvedUrl = '';
    await client.initialize(
      approveLaunch: (command, arguments) async {
        approvedUrl = command;
        return true;
      },
    );

    expect(approvedUrl, 'https://mcp.test/rpc');
    expect(client.tools.map((tool) => tool.name), ['echo']);
    expect(await client.callTool('echo', {'value': 'x'}), 'halo mcp');
  });

  test(
    'MCP HTTP resolves credential references only at request time',
    () async {
      var authorization = '';
      final server = MockClient((request) async {
        authorization = request.headers['authorization'] ?? '';
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final id = body['id'];
        final method = body['method'];
        if (method == 'notifications/initialized') {
          return http.Response('', 202);
        }
        return http.Response(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': id,
            'result': method == 'initialize'
                ? {
                    'protocolVersion': '2025-03-26',
                    'serverInfo': {'name': 'test', 'version': '1'},
                  }
                : {'tools': []},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final client = McpClient(
        const McpServerConfig(
          name: 'remote',
          transport: McpTransport.http,
          url: 'https://mcp.test/rpc',
          headerReferences: {'Authorization': 'mcp.remote.authorization'},
        ),
        workspace: '.',
        httpClient: server,
        resolveCredential: (reference) async =>
            reference == 'mcp.remote.authorization'
            ? 'Bearer runtime-value'
            : null,
      );
      addTearDown(client.dispose);

      await client.initialize(approveLaunch: (_, _) async => true);

      expect(authorization, 'Bearer runtime-value');
      expect(
        client.config.toJson().toString(),
        isNot(contains('runtime-value')),
      );
    },
  );

  test('MCP HTTP initialize paralel berbagi handshake yang sama', () async {
    final release = Completer<void>();
    var initializeCount = 0;
    final server = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      if (body['method'] == 'initialize') {
        initializeCount++;
        await release.future;
      }
      return _baseProtocolResponse(body);
    });
    final client = _client(server);
    addTearDown(client.dispose);

    final first = client.initialize(approveLaunch: (_, _) async => true);
    await Future<void>.delayed(Duration.zero);
    final second = client.initialize(approveLaunch: (_, _) async => true);

    expect(identical(first, second), isTrue);
    expect(client.status, McpConnectionStatus.connecting);
    expect(initializeCount, 1);
    release.complete();
    await Future.wait([first, second]);
    expect(client.status, McpConnectionStatus.ready);
  });

  test(
    'MCP HTTP dispose membatalkan initialize yang sedang berjalan',
    () async {
      final release = Completer<void>();
      final server = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (body['method'] == 'initialize') await release.future;
        return _baseProtocolResponse(body);
      });
      final client = _client(server);

      final initializing = client.initialize(
        approveLaunch: (_, _) async => true,
      );
      await Future<void>.delayed(Duration.zero);
      await client.dispose();
      release.complete();

      await expectLater(initializing, throwsA(isA<StateError>()));
      expect(client.status, McpConnectionStatus.disconnected);
    },
  );

  test(
    'MCP HTTP retry setelah initialize gagal melakukan handshake baru',
    () async {
      var initializeCount = 0;
      final server = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final method = body['method'];
        final id = body['id'];
        if (method == 'initialize') {
          initializeCount++;
          if (initializeCount == 1) return http.Response('temporary', 500);
          return http.Response(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': id,
              'result': {
                'protocolVersion': '2025-03-26',
                'serverInfo': {'name': 'test'},
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (method == 'notifications/initialized') {
          return http.Response('', 202);
        }
        return http.Response(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': id,
            'result': {'tools': []},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final client = _client(server);
      addTearDown(client.dispose);

      await expectLater(
        client.initialize(approveLaunch: (_, _) async => true),
        throwsA(isA<StateError>()),
      );
      await client.initialize(approveLaunch: (_, _) async => true);

      expect(initializeCount, 2);
      expect(client.status, McpConnectionStatus.ready);
    },
  );

  test(
    'MCP HTTP menunggu initialized notification sebelum tools/list',
    () async {
      var notificationComplete = false;
      final server = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final method = body['method'];
        final id = body['id'];
        if (method == 'initialize') {
          return http.Response(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': id,
              'result': {'protocolVersion': '2025-03-26'},
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (method == 'notifications/initialized') {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          notificationComplete = true;
          return http.Response('', 202);
        }
        expect(notificationComplete, isTrue);
        return http.Response(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': id,
            'result': {'tools': []},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final client = _client(server);
      addTearDown(client.dispose);

      await client.initialize(approveLaunch: (_, _) async => true);
      expect(client.status, McpConnectionStatus.ready);
    },
  );

  test('MCP HTTP menangani respons tool/call ber-SSE', () async {
    final client = _client(_server(sseToolCall: true));
    addTearDown(client.dispose);
    await client.initialize(approveLaunch: (_, _) async => true);
    expect(await client.callTool('echo', {}), 'halo mcp');
  });

  test('MCP HTTP merekonstruksi multiline SSE event', () async {
    final server = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      if (body['method'] != 'tools/call') return _baseProtocolResponse(body);
      final payload = jsonEncode({
        'jsonrpc': '2.0',
        'id': body['id'],
        'result': {
          'content': [
            {'type': 'text', 'text': 'multiline'},
          ],
        },
      });
      final split = payload.indexOf('"result"');
      return http.Response(
        'data: ${payload.substring(0, split)}\n'
        'data: ${payload.substring(split)}\n\n',
        200,
        headers: {'content-type': 'text/event-stream'},
      );
    });
    final client = _client(server);
    addTearDown(client.dispose);
    await client.initialize(approveLaunch: (_, _) async => true);
    expect(await client.callTool('echo', {}), 'multiline');
  });

  test('MCP JSON-RPC error tidak merefleksikan credential runtime', () async {
    const secret = 'Bearer reflected-secret-value-1234567890';
    final server = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      if (body['method'] != 'tools/call') return _baseProtocolResponse(body);
      return http.Response(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': body['id'],
          'error': {'code': -32000, 'message': 'Authorization: $secret'},
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final client = _client(server);
    addTearDown(client.dispose);
    await client.initialize(approveLaunch: (_, _) async => true);

    await expectLater(
      client.callTool('echo', {}),
      throwsA(
        isA<StateError>().having(
          (error) => '$error',
          'message',
          isNot(contains('reflected-secret-value')),
        ),
      ),
    );
  });

  test('MCP HTTP memakai absolute deadline untuk slow-drip body', () async {
    final client = McpClient(
      const McpServerConfig(
        name: 'slow',
        transport: McpTransport.http,
        url: 'https://mcp.test/rpc',
      ),
      workspace: '.',
      httpClient: _SlowDripClient(),
      requestTimeout: const Duration(milliseconds: 30),
    );
    addTearDown(client.dispose);

    await expectLater(
      client.initialize(approveLaunch: (_, _) async => true),
      throwsA(isA<StateError>()),
    );
    expect(client.status, McpConnectionStatus.failed);
  });

  test('MCP HTTP menolak response body di atas batas', () async {
    final server = MockClient(
      (_) async => http.Response(
        'x' * (2 * 1024 * 1024 + 1),
        200,
        headers: {'content-type': 'application/json'},
      ),
    );
    final client = _client(server);
    addTearDown(client.dispose);

    await expectLater(
      client.initialize(approveLaunch: (_, _) async => true),
      throwsA(
        isA<StateError>().having(
          (error) => '$error',
          'message',
          contains('melebihi batas'),
        ),
      ),
    );
  });

  test('MCP HTTP meredaksi secret dari error dan logs', () async {
    const token = 'bearer-secret-value-1234567890';
    final server = MockClient(
      (_) async => http.Response(
        'Authorization: Bearer $token',
        401,
        headers: {'content-type': 'text/plain'},
      ),
    );
    final client = _client(server);
    addTearDown(client.dispose);

    Object? error;
    try {
      await client.initialize(approveLaunch: (_, _) async => true);
    } catch (caught) {
      error = caught;
    }

    expect(error, isNotNull);
    expect('$error', isNot(contains(token)));
    expect(client.logs.join('\n'), isNot(contains(token)));
  });

  test(
    'MCP HTTP memulihkan session expired untuk tools/list tanpa replay call',
    () async {
      var initializeCount = 0;
      var listCount = 0;
      final server = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final method = body['method'];
        final id = body['id'];
        if (method == 'initialize') {
          initializeCount++;
          return http.Response(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': id,
              'result': {
                'protocolVersion': '2025-03-26',
                'serverInfo': {'name': 'test', 'version': '1'},
              },
            }),
            200,
            headers: {
              'content-type': 'application/json',
              'mcp-session-id': 'session-$initializeCount',
            },
          );
        }
        if (method == 'notifications/initialized') {
          return http.Response('', 202);
        }
        if (method == 'tools/list') {
          listCount++;
          if (listCount == 2) return http.Response('expired', 404);
          return http.Response(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': id,
              'result': {'tools': []},
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{}', 400);
      });
      final client = _client(server);
      addTearDown(client.dispose);
      await client.initialize(approveLaunch: (_, _) async => true);

      await client.refreshTools();

      expect(initializeCount, 2);
      expect(listCount, 3);
    },
  );

  test('MCP HTTP membatasi jumlah tool discovery', () async {
    final tooManyTools = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final id = body['id'];
      final method = body['method'];
      if (method == 'initialize') {
        return http.Response(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': id,
            'result': {
              'protocolVersion': '2025-03-26',
              'serverInfo': {'name': 'test', 'version': '1'},
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (method == 'notifications/initialized') {
        return http.Response('', 202);
      }
      return http.Response(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': id,
          'result': {
            'tools': [
              for (var index = 0; index < 257; index++)
                {
                  'name': 'tool_$index',
                  'inputSchema': {'type': 'object'},
                },
            ],
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final client = _client(tooManyTools);
    addTearDown(client.dispose);

    await expectLater(
      client.initialize(approveLaunch: (_, _) async => true),
      throwsA(isA<StateError>()),
    );
  });

  test('MCP HTTP menolak schema tool yang terlalu kompleks', () async {
    Map<String, dynamic> schema = {'type': 'string'};
    for (var depth = 0; depth < 18; depth++) {
      schema = {
        'type': 'object',
        'properties': {'nested': schema},
      };
    }
    final server = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final id = body['id'];
      final method = body['method'];
      if (method == 'initialize') {
        return http.Response(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': id,
            'result': {
              'protocolVersion': '2025-03-26',
              'serverInfo': {'name': 'test', 'version': '1'},
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (method == 'notifications/initialized') {
        return http.Response('', 202);
      }
      return http.Response(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': id,
          'result': {
            'tools': [
              {'name': 'deep', 'inputSchema': schema},
            ],
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final client = _client(server);
    addTearDown(client.dispose);

    await expectLater(
      client.initialize(approveLaunch: (_, _) async => true),
      throwsA(
        isA<StateError>().having(
          (error) => '$error',
          'message',
          contains('schema'),
        ),
      ),
    );
  });

  test('MCP HTTP membatasi output tool menjadi 1 MiB', () async {
    final server = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final method = body['method'];
      final id = body['id'];
      if (method == 'initialize') {
        return http.Response(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': id,
            'result': {
              'protocolVersion': '2025-03-26',
              'serverInfo': {'name': 'test', 'version': '1'},
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (method == 'notifications/initialized') {
        return http.Response('', 202);
      }
      if (method == 'tools/list') {
        return http.Response(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': id,
            'result': {
              'tools': [
                {
                  'name': 'large',
                  'inputSchema': {'type': 'object'},
                },
              ],
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': id,
          'result': {
            'content': [
              {'type': 'text', 'text': 'x' * (1024 * 1024 + 1)},
            ],
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final client = _client(server);
    addTearDown(client.dispose);
    await client.initialize(approveLaunch: (_, _) async => true);

    await expectLater(client.callTool('large', {}), throwsA(isA<StateError>()));
  });

  test('MCP HTTP menolak peluncuran yang tidak disetujui', () async {
    final client = _client(_server());
    addTearDown(client.dispose);
    await expectLater(
      client.initialize(approveLaunch: (_, _) async => false),
      throwsA(isA<StateError>()),
    );
  });

  test('MCP HTTP menolak URL non-HTTPS non-loopback', () async {
    final client = McpClient(
      const McpServerConfig(
        name: 'insecure',
        transport: McpTransport.http,
        url: 'http://mcp.evil/rpc',
      ),
      workspace: '.',
      httpClient: _server(),
    );
    addTearDown(client.dispose);
    await expectLater(
      client.initialize(approveLaunch: (_, _) async => true),
      throwsA(isA<StateError>()),
    );
  });
}
