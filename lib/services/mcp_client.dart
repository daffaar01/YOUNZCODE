import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../models/addon.dart';
import 'process_launch.dart';
import 'secret_scanner.dart';

typedef McpLaunchApproval =
    Future<bool> Function(String command, List<String> arguments);
typedef McpCredentialResolver = Future<String?> Function(String reference);
typedef McpEndpointLookup = Future<List<InternetAddress>> Function(String host);
typedef McpSecureSocket =
    Future<SecureSocket> Function(Socket socket, String host);
typedef McpSocketConnect =
    Future<ConnectionTask<Socket>> Function(InternetAddress address, int port);

Future<void> validateMcpHttpEndpoint(
  Uri uri, {
  McpEndpointLookup lookup = InternetAddress.lookup,
}) async {
  if (uri.userInfo.isNotEmpty || uri.host.isEmpty || uri.fragment.isNotEmpty) {
    throw StateError('MCP HTTP endpoint tidak valid.');
  }
  if (_isLoopback(uri)) {
    if (!uri.isScheme('http') && !uri.isScheme('https')) {
      throw StateError('MCP loopback endpoint must use HTTP or HTTPS.');
    }
    return;
  }
  if (!uri.isScheme('https')) {
    throw StateError('MCP remote endpoint must use HTTPS.');
  }
  final addresses = await lookup(uri.host);
  if (addresses.isEmpty || addresses.any(_isNonPublicAddress)) {
    throw StateError('MCP remote endpoint resolved to a non-public address.');
  }
}

Future<InternetAddress> resolveMcpConnectAddress(
  Uri uri, {
  McpEndpointLookup lookup = InternetAddress.lookup,
}) async {
  if (uri.userInfo.isNotEmpty || uri.host.isEmpty || uri.fragment.isNotEmpty) {
    throw StateError('MCP HTTP endpoint tidak valid.');
  }
  final loopback = _isLoopback(uri);
  if (loopback) {
    if (!uri.isScheme('http') && !uri.isScheme('https')) {
      throw StateError('MCP loopback endpoint must use HTTP or HTTPS.');
    }
  } else if (!uri.isScheme('https')) {
    throw StateError('MCP remote endpoint must use HTTPS.');
  }
  // This single lookup supplies the exact address used by connectionFactory;
  // there is no second DNS resolution between policy and socket connection.
  final addresses = await lookup(uri.host);
  if (addresses.isEmpty) {
    throw StateError('MCP endpoint tidak memiliki alamat koneksi.');
  }
  if (loopback) {
    if (addresses.any((address) => !address.isLoopback)) {
      throw StateError('MCP loopback endpoint resolution tidak aman.');
    }
  } else if (addresses.any(_isNonPublicAddress)) {
    throw StateError('MCP remote endpoint resolved to a non-public address.');
  }
  return addresses.first;
}

http.Client createPinnedMcpHttpClient(
  McpEndpointLookup lookup, {
  McpSocketConnect connect = Socket.startConnect,
  McpSecureSocket secure = _secureMcpSocket,
}) {
  final native = HttpClient()..findProxy = (_) => 'DIRECT';
  native.connectionFactory = (uri, proxyHost, proxyPort) async {
    if (proxyHost != null || proxyPort != null) {
      throw StateError('MCP proxy connection tidak diizinkan.');
    }
    final address = await resolveMcpConnectAddress(uri, lookup: lookup);
    final port = uri.hasPort ? uri.port : (uri.isScheme('https') ? 443 : 80);
    final connection = await connect(address, port);
    Socket? activeSocket;
    final cancelled = Completer<Socket>();

    final socket = Future.any<Socket>([connection.socket, cancelled.future])
        .then<Socket>((plain) async {
          activeSocket = plain;
          if (!uri.isScheme('https')) return plain;
          final securing = secure(plain, uri.host);
          unawaited(
            securing.then((secured) {
              if (cancelled.isCompleted) secured.destroy();
            }, onError: (_) {}),
          );
          final secured = await Future.any<Socket>([
            securing,
            cancelled.future,
          ]);
          activeSocket = secured;
          return secured;
        });

    return ConnectionTask.fromSocket<Socket>(socket, () {
      if (!cancelled.isCompleted) {
        cancelled.completeError(
          const SocketException('Connection attempt cancelled'),
        );
      }
      activeSocket?.destroy();
      connection.cancel();
    });
  };
  return IOClient(native);
}

Future<SecureSocket> _secureMcpSocket(Socket socket, String host) =>
    SecureSocket.secure(socket, host: host);

bool _isNonPublicAddress(InternetAddress address) {
  final bytes = address.rawAddress;
  if (address.type == InternetAddressType.IPv4) {
    return _isNonPublicIpv4(bytes);
  }
  if (bytes.every((value) => value == 0) || address.isLoopback) return true;

  // IPv4-mapped IPv6 (::ffff:a.b.c.d) must inherit the IPv4 policy.
  final ipv4Mapped =
      bytes.length == 16 &&
      bytes.take(10).every((value) => value == 0) &&
      bytes[10] == 0xff &&
      bytes[11] == 0xff;
  if (ipv4Mapped) return _isNonPublicIpv4(bytes.sublist(12));

  return bytes[0] == 0xfc ||
      bytes[0] == 0xfd ||
      (bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80) ||
      bytes[0] == 0xff ||
      (bytes[0] == 0x20 &&
          bytes[1] == 0x01 &&
          bytes[2] == 0x0d &&
          bytes[3] == 0xb8);
}

bool _isNonPublicIpv4(List<int> bytes) {
  final a = bytes[0];
  final b = bytes[1];
  final c = bytes[2];
  return a == 0 ||
      a == 10 ||
      (a == 100 && b >= 64 && b <= 127) ||
      a == 127 ||
      (a == 169 && b == 254) ||
      (a == 172 && b >= 16 && b <= 31) ||
      (a == 192 && b == 0 && c == 0) ||
      (a == 192 && b == 0 && c == 2) ||
      (a == 192 && b == 88 && c == 99) ||
      (a == 192 && b == 168) ||
      (a == 198 && (b == 18 || b == 19)) ||
      (a == 198 && b == 51 && c == 100) ||
      (a == 203 && b == 0 && c == 113) ||
      a >= 224;
}

bool _isLoopback(Uri uri) {
  final host = uri.host.toLowerCase();
  return host == 'localhost' || host == '::1' || host.startsWith('127.');
}

enum McpConnectionStatus { disconnected, connecting, ready, failed }

class McpTool {
  const McpTool({
    required this.name,
    required this.description,
    required this.inputSchema,
  });

  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;
}

class McpHealth {
  const McpHealth({
    required this.serverName,
    required this.transport,
    required this.status,
    required this.latency,
    required this.tools,
    required this.logs,
    this.error = '',
  });

  final String serverName;
  final McpTransport transport;
  final McpConnectionStatus status;
  final Duration latency;
  final List<McpTool> tools;
  final List<String> logs;
  final String error;

  bool get healthy => status == McpConnectionStatus.ready;
}

class McpClient {
  McpClient(
    this.config, {
    required this.workspace,
    http.Client? httpClient,
    McpCredentialResolver? resolveCredential,
    McpEndpointLookup? endpointLookup,
    Duration requestTimeout = const Duration(seconds: 30),
  }) : _injectedHttpClient = httpClient,
       _resolveCredential = resolveCredential,
       _endpointLookup =
           endpointLookup ??
           ((host) => httpClient != null && host.endsWith('.test')
               ? Future.value([InternetAddress('8.8.8.8')])
               : InternetAddress.lookup(host)),
       _requestTimeout = requestTimeout;

  final McpServerConfig config;
  final String workspace;
  final http.Client? _injectedHttpClient;
  final McpCredentialResolver? _resolveCredential;
  final McpEndpointLookup _endpointLookup;
  final Duration _requestTimeout;
  Process? _process;
  StreamSubscription<String>? _stdout;
  StreamSubscription<String>? _stderr;
  http.Client? _httpClient; // active client for Streamable HTTP transport
  String? _sessionId;
  final _pending = <int, Completer<Map<String, dynamic>>>{};
  int _sequence = 1;
  List<McpTool> _tools = const [];
  McpConnectionStatus _status = McpConnectionStatus.disconnected;
  String _lastError = '';
  Map<String, dynamic> _serverInfo = const {};
  final List<String> _logs = [];
  Future<void>? _initializing;
  int _lifecycleGeneration = 0;

  bool get _isHttp => config.transport == McpTransport.http;

  List<McpTool> get tools => _tools;
  McpConnectionStatus get status => _status;
  String get lastError => _lastError;
  Map<String, dynamic> get serverInfo => Map.unmodifiable(_serverInfo);
  List<String> get logs => List.unmodifiable(_logs);

  Future<void> initialize({required McpLaunchApproval approveLaunch}) {
    if (_status == McpConnectionStatus.ready) return Future.value();
    final active = _initializing;
    if (active != null) return active;
    final generation = ++_lifecycleGeneration;
    late final Future<void> future;
    future = _runInitialize(approveLaunch, generation).whenComplete(() {
      if (identical(_initializing, future)) _initializing = null;
    });
    _initializing = future;
    return future;
  }

  Future<void> _runInitialize(
    McpLaunchApproval approveLaunch,
    int generation,
  ) async {
    _status = McpConnectionStatus.connecting;
    _lastError = '';
    _log('Connecting via ${config.transport.name}');
    try {
      if (_isHttp) {
        await _initializeHttp(approveLaunch);
      } else {
        await _initializeStdio(approveLaunch);
      }
      if (generation != _lifecycleGeneration) {
        throw StateError('MCP initialization was cancelled.');
      }
      _status = McpConnectionStatus.ready;
      _log('Ready with ${_tools.length} tools');
    } catch (error, stackTrace) {
      if (generation != _lifecycleGeneration) {
        _resetHttpAfterFailure();
        Error.throwWithStackTrace(
          StateError('MCP initialization was cancelled.'),
          stackTrace,
        );
      }
      if (_isHttp) _resetHttpAfterFailure();
      _status = McpConnectionStatus.failed;
      _lastError = _sanitize('$error');
      _log('Connection failed: $_lastError');
      Error.throwWithStackTrace(StateError(_lastError), stackTrace);
    }
  }

  Future<void> _initializeStdio(McpLaunchApproval approveLaunch) async {
    if (_process != null) return;
    if (config.command == null) {
      throw StateError('MCP stdio server requires a command.');
    }
    if (!await approveLaunch(config.command!, config.arguments)) {
      throw StateError('MCP server launch was denied.');
    }
    // runInShell: false keeps shell metacharacters in arguments (e.g. `&` or
    // spaces in a server path) out of the command line; batch wrappers are
    // re-routed through cmd.exe without interpreting the arguments.
    final launch = resolveProcessLaunch(config.command!, config.arguments);
    final process = await Process.start(
      launch.executable,
      launch.arguments,
      workingDirectory: workspace,
      environment: {...Platform.environment, ...config.environment},
      runInShell: false,
    );
    _process = process;
    _stdout = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleLine);
    _stderr = process.stderr
        .transform(utf8.decoder)
        .listen((message) => _log('stderr: ${message.trim()}'));
    unawaited(process.exitCode.then((_) => _closePending()));
    final initialized = await _request('initialize', {
      'protocolVersion': '2025-03-26',
      'capabilities': {},
      'clientInfo': {'name': 'YOUNZCODE', 'version': '1.1.0'},
    });
    _serverInfo = Map<String, dynamic>.from(
      initialized['serverInfo'] as Map? ?? const {},
    );
    await _notify('notifications/initialized');
    await refreshTools();
  }

  Future<void> _initializeHttp(McpLaunchApproval approveLaunch) async {
    if (_httpClient != null) return;
    final url = config.url?.trim() ?? '';
    final uri = Uri.tryParse(url);
    if (url.isEmpty || uri == null || !uri.hasScheme) {
      throw StateError('MCP HTTP url tidak valid.');
    }
    await validateMcpHttpEndpoint(uri, lookup: _endpointLookup);
    if (!await approveLaunch(url, const [])) {
      throw StateError('MCP server launch was denied.');
    }
    _httpClient =
        _injectedHttpClient ?? createPinnedMcpHttpClient(_endpointLookup);
    final initialized = await _request('initialize', {
      'protocolVersion': '2025-03-26',
      'capabilities': {},
      'clientInfo': {'name': 'YOUNZCODE', 'version': '1.1.0'},
    });
    _serverInfo = Map<String, dynamic>.from(
      initialized['serverInfo'] as Map? ?? const {},
    );
    await _notify('notifications/initialized');
    await refreshTools();
  }

  Future<McpHealth> healthCheck({
    required McpLaunchApproval approveLaunch,
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      await initialize(approveLaunch: approveLaunch);
      await refreshTools();
      stopwatch.stop();
      return McpHealth(
        serverName: config.name,
        transport: config.transport,
        status: _status,
        latency: stopwatch.elapsed,
        tools: List.unmodifiable(_tools),
        logs: List.unmodifiable(_logs),
      );
    } catch (error) {
      stopwatch.stop();
      return McpHealth(
        serverName: config.name,
        transport: config.transport,
        status: McpConnectionStatus.failed,
        latency: stopwatch.elapsed,
        tools: List.unmodifiable(_tools),
        logs: List.unmodifiable(_logs),
        error: '$error',
      );
    }
  }

  Future<void> refreshTools() async {
    final result = await _request('tools/list');
    final values = result['tools'] as List? ?? const [];
    if (values.length > 256) {
      throw StateError('MCP tool discovery melebihi batas 256 tools.');
    }
    final tools = <McpTool>[];
    for (final value in values) {
      if (value is! Map) continue;
      final tool = Map<String, dynamic>.from(value);
      final name = tool['name'];
      if (name is! String || name.isEmpty) continue; // skip malformed entry
      if (name.length > 128) {
        throw StateError('MCP tool name melebihi batas 128 karakter.');
      }
      final description = tool['description'] as String? ?? '';
      if (description.length > 16000) {
        throw StateError('MCP tool description melebihi batas 16000 karakter.');
      }
      final inputSchema = tool['inputSchema'] is Map
          ? Map<String, dynamic>.from(tool['inputSchema'] as Map)
          : const <String, dynamic>{'type': 'object'};
      _validateSchemaBudget(inputSchema);
      tools.add(
        McpTool(name: name, description: description, inputSchema: inputSchema),
      );
    }
    _tools = tools;
  }

  static void _validateSchemaBudget(Map<String, dynamic> schema) {
    if (utf8.encode(jsonEncode(schema)).length > 256 * 1024) {
      throw StateError('MCP tool schema melebihi batas 256 KiB.');
    }
    var nodes = 0;
    void visit(Object? value, int depth) {
      nodes++;
      if (depth > 16 || nodes > 4096) {
        throw StateError('MCP tool schema melebihi batas kompleksitas.');
      }
      if (value is Map) {
        for (final entry in value.entries) {
          visit(entry.key, depth + 1);
          visit(entry.value, depth + 1);
        }
      } else if (value is List) {
        for (final item in value) {
          visit(item, depth + 1);
        }
      }
    }

    visit(schema, 0);
  }

  Future<String> callTool(String name, Map<String, dynamic> arguments) async {
    final result = await _request('tools/call', {
      'name': name,
      'arguments': arguments,
    });
    final output = <String>[];
    for (final raw in result['content'] as List? ?? const []) {
      final content = Map<String, dynamic>.from(raw as Map);
      if (content['type'] == 'text') output.add('${content['text'] ?? ''}');
    }
    if (result['structuredContent'] != null) {
      output.add(jsonEncode(result['structuredContent']));
    }
    if (output.isEmpty) output.add(jsonEncode(result));
    final rendered =
        '${result['isError'] == true ? 'MCP error: ' : ''}${output.join('\n')}';
    if (utf8.encode(rendered).length > 1024 * 1024) {
      throw StateError('MCP tool output melebihi batas 1 MiB.');
    }
    return rendered;
  }

  Future<Map<String, dynamic>> _request(
    String method, [
    Map<String, dynamic>? params,
  ]) async {
    if (_isHttp) return _httpRequest(method, params);
    final process = _process;
    if (process == null) throw StateError('MCP server is not running.');
    final id = _sequence++;
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    process.stdin.writeln(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        'params': params,
      }),
    );
    await process.stdin.flush();
    return completer.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () {
        _pending.remove(id);
        throw TimeoutException(
          'MCP server ${config.name} did not answer $method.',
        );
      },
    );
  }

  Future<void> _notify(String method, [Map<String, dynamic>? params]) async {
    if (_isHttp) {
      await _httpRequest(method, params, isNotification: true);
      return;
    }
    _process?.stdin.writeln(
      jsonEncode({'jsonrpc': '2.0', 'method': method, 'params': params}),
    );
    await _process?.stdin.flush();
  }

  void _resetHttpAfterFailure() {
    if (_injectedHttpClient == null) _httpClient?.close();
    _httpClient = null;
    _sessionId = null;
    _serverInfo = {};
    _tools = [];
  }

  Future<Map<String, String>> _resolvedHttpHeaders() async {
    if (config.headerReferences.isEmpty) return const {};
    final resolver = _resolveCredential;
    if (resolver == null) {
      throw StateError('MCP credential resolver tidak tersedia.');
    }
    final headers = <String, String>{};
    for (final entry in config.headerReferences.entries) {
      final name = entry.key.trim();
      final reference = entry.value.trim();
      if (name.isEmpty ||
          name.length > 128 ||
          reference.isEmpty ||
          reference.length > 512 ||
          const {
            'content-type',
            'accept',
            'mcp-session-id',
          }.contains(name.toLowerCase())) {
        throw StateError('MCP credential header reference tidak valid.');
      }
      final value = await resolver(reference);
      if (value == null || value.isEmpty || value.length > 16384) {
        throw StateError('MCP credential reference tidak dapat diselesaikan.');
      }
      headers[name] = value;
    }
    return headers;
  }

  Future<Map<String, dynamic>> _httpRequest(
    String method,
    Map<String, dynamic>? params, {
    bool isNotification = false,
    bool allowSessionRecovery = true,
  }) async {
    final client = _httpClient;
    final url = config.url;
    if (client == null || url == null) {
      throw StateError('MCP HTTP client is not running.');
    }
    if (config.headers.keys.any(isSensitiveMcpHeaderName)) {
      throw StateError('Sensitive MCP headers must use headerReferences.');
    }
    final endpoint = Uri.parse(url);
    await validateMcpHttpEndpoint(endpoint, lookup: _endpointLookup);
    final id = _sequence++;
    final resolvedHeaders = await _resolvedHttpHeaders();
    final request = http.Request('POST', endpoint)
      ..followRedirects = false
      ..headers.addAll({
        ...config.headers,
        ...resolvedHeaders,
        'Content-Type': 'application/json',
        'Accept': 'application/json, text/event-stream',
        'Mcp-Session-Id': ?_sessionId,
      })
      ..body = jsonEncode({
        'jsonrpc': '2.0',
        if (!isNotification) 'id': id,
        'method': method,
        'params': ?params,
      });
    final stopwatch = Stopwatch()..start();
    final streamed = await client.send(request).timeout(_requestTimeout);
    final remaining = _requestTimeout - stopwatch.elapsed;
    if (remaining <= Duration.zero) {
      throw TimeoutException('MCP request exceeded its absolute deadline.');
    }
    if (streamed.isRedirect ||
        (streamed.statusCode >= 300 && streamed.statusCode < 400)) {
      unawaited(streamed.stream.listen((_) {}).cancel());
      throw StateError('MCP redirects are not allowed.');
    }
    final bytes = await _collectBoundedBody(
      streamed.stream,
      remaining,
      contentType: streamed.headers['content-type'] ?? '',
      expectedId: isNotification ? null : id,
    );
    stopwatch.stop();
    final response = http.Response.bytes(
      bytes,
      streamed.statusCode,
      headers: streamed.headers,
      request: request,
      isRedirect: streamed.isRedirect,
      persistentConnection: streamed.persistentConnection,
      reasonPhrase: streamed.reasonPhrase,
    );
    final session = response.headers['mcp-session-id'];
    if (session != null && session.isNotEmpty) _sessionId = session;
    if (allowSessionRecovery &&
        method == 'tools/list' &&
        (response.statusCode == 404 || response.statusCode == 410)) {
      await _recoverHttpSession();
      return _httpRequest(method, params, allowSessionRecovery: false);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final safeBody = _sanitize(response.body, resolvedHeaders.values);
      throw StateError(
        'MCP ${config.name} HTTP ${response.statusCode}: '
        '${safeBody.length <= 4096 ? safeBody : safeBody.substring(0, 4096)}',
      );
    }
    if (isNotification) return const {};
    return _extractJsonRpcResult(
      response,
      id,
      method,
      exactSecrets: resolvedHeaders.values,
    );
  }

  Future<Uint8List> _collectBoundedBody(
    Stream<List<int>> stream,
    Duration deadline, {
    required String contentType,
    required int? expectedId,
  }) async {
    final body = BytesBuilder(copy: false);
    final completer = Completer<Uint8List>();
    late StreamSubscription<List<int>> subscription;
    final timer = Timer(deadline, () {
      unawaited(subscription.cancel());
      if (!completer.isCompleted) {
        completer.completeError(
          TimeoutException('MCP request exceeded its absolute deadline.'),
        );
      }
    });
    subscription = stream.listen(
      (chunk) {
        if (body.length + chunk.length > 2 * 1024 * 1024) {
          unawaited(subscription.cancel());
          if (!completer.isCompleted) {
            completer.completeError(
              StateError('MCP response melebihi batas 2 MiB.'),
            );
          }
          return;
        }
        body.add(chunk);
        if (expectedId != null &&
            contentType.toLowerCase().contains('text/event-stream')) {
          final current = utf8.decode(body.toBytes(), allowMalformed: true);
          final normalized = current.replaceAll('\r\n', '\n');
          for (final event in normalized.split('\n\n')) {
            final data = const LineSplitter()
                .convert(event)
                .where((line) => line.startsWith('data:'))
                .map((line) => line.substring(5).trimLeft())
                .join('\n');
            final decoded = _tryDecode(data);
            if (decoded is Map && decoded['id'] == expectedId) {
              unawaited(subscription.cancel());
              if (!completer.isCompleted) {
                completer.complete(
                  Uint8List.fromList(utf8.encode('$event\n\n')),
                );
              }
              return;
            }
          }
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      },
      onDone: () {
        if (!completer.isCompleted) completer.complete(body.takeBytes());
      },
      cancelOnError: true,
    );
    try {
      return await completer.future;
    } finally {
      timer.cancel();
    }
  }

  Future<void> _recoverHttpSession() async {
    _sessionId = null;
    final initialized = await _httpRequest('initialize', {
      'protocolVersion': '2025-03-26',
      'capabilities': {},
      'clientInfo': {'name': 'YOUNZCODE', 'version': '1.1.0'},
    }, allowSessionRecovery: false);
    _serverInfo = Map<String, dynamic>.from(
      initialized['serverInfo'] as Map? ?? const {},
    );
    await _httpRequest(
      'notifications/initialized',
      null,
      isNotification: true,
      allowSessionRecovery: false,
    );
    _log('HTTP session recovered');
  }

  Map<String, dynamic> _extractJsonRpcResult(
    http.Response response,
    int id,
    String method, {
    Iterable<String> exactSecrets = const [],
  }) {
    final contentType = (response.headers['content-type'] ?? '').toLowerCase();
    final body = utf8.decode(response.bodyBytes);
    final messages = <Map<String, dynamic>>[];
    if (contentType.contains('text/event-stream')) {
      final dataLines = <String>[];
      void dispatchEvent() {
        if (dataLines.isEmpty) return;
        final data = dataLines.join('\n');
        dataLines.clear();
        if (data.trim() == '[DONE]') return;
        final decoded = _tryDecode(data);
        if (decoded is Map) messages.add(Map<String, dynamic>.from(decoded));
      }

      for (final line in const LineSplitter().convert(body)) {
        if (line.isEmpty) {
          dispatchEvent();
        } else if (line.startsWith('data:')) {
          final value = line.substring(5);
          dataLines.add(value.startsWith(' ') ? value.substring(1) : value);
        }
      }
      dispatchEvent();
    } else {
      final decoded = _tryDecode(body);
      if (decoded is Map) {
        messages.add(Map<String, dynamic>.from(decoded));
      } else if (decoded is List) {
        for (final item in decoded) {
          if (item is Map) messages.add(Map<String, dynamic>.from(item));
        }
      }
    }
    for (final message in messages) {
      if (message['method'] == 'notifications/tools/list_changed') {
        unawaited(refreshTools().catchError((_) {}));
      }
    }
    for (final message in messages) {
      if (message['id'] != id) continue;
      if (message['error'] != null) {
        throw StateError(
          'MCP ${config.name}: '
          '${_sanitize('${message['error']}', exactSecrets)}',
        );
      }
      final result = Map<String, dynamic>.from(
        message['result'] as Map? ?? const {},
      );
      return Map<String, dynamic>.from(
        _sanitizeJsonValue(result, exactSecrets) as Map,
      );
    }
    throw StateError('MCP ${config.name}: tidak ada respons untuk $method.');
  }

  static Object? _sanitizeJsonValue(
    Object? value,
    Iterable<String> exactSecrets,
  ) {
    if (value is String) return _sanitize(value, exactSecrets);
    if (value is List) {
      return value
          .map((item) => _sanitizeJsonValue(item, exactSecrets))
          .toList(growable: false);
    }
    if (value is Map) {
      final sanitized = <Object?, Object?>{};
      for (final entry in value.entries) {
        final key = entry.key is String
            ? _sanitize(entry.key as String, exactSecrets)
            : entry.key;
        sanitized[key] = _sanitizeJsonValue(entry.value, exactSecrets);
      }
      return sanitized;
    }
    return value;
  }

  static Object? _tryDecode(String value) {
    try {
      return jsonDecode(value);
    } on FormatException {
      return null;
    }
  }

  void _handleLine(String line) {
    if (line.trim().isEmpty) return;
    try {
      final message = Map<String, dynamic>.from(jsonDecode(line) as Map);
      if (message['method'] == 'notifications/tools/list_changed') {
        // Fire-and-forget refresh must swallow its own errors; otherwise a
        // malformed tools/list or a timeout becomes an unhandled async crash.
        unawaited(refreshTools().catchError((_) {}));
        return;
      }
      final id = message['id'];
      if (id is! int) return;
      final completer = _pending.remove(id);
      if (completer == null) return;
      if (message['error'] != null) {
        completer.completeError(
          StateError('MCP ${config.name}: ${message['error']}'),
        );
      } else {
        completer.complete(
          Map<String, dynamic>.from(message['result'] as Map? ?? const {}),
        );
      }
    } catch (_) {
      // Non-protocol stdout is ignored; well-behaved MCP servers log to stderr.
    }
  }

  void _closePending() {
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(
          StateError('MCP server ${config.name} stopped.'),
        );
      }
    }
    _pending.clear();
    _process = null;
    if (_status == McpConnectionStatus.ready) {
      _status = McpConnectionStatus.failed;
      _lastError = 'MCP server stopped.';
      _log(_lastError);
    }
  }

  Future<void> dispose() async {
    _lifecycleGeneration++;
    if (_isHttp) {
      final client = _httpClient;
      _httpClient = null;
      _sessionId = null;
      if (_injectedHttpClient == null) client?.close();
      _status = McpConnectionStatus.disconnected;
      _log('Disconnected');
      return;
    }
    final process = _process;
    _process = null;
    await _stdout?.cancel();
    await _stderr?.cancel();
    try {
      await process?.stdin.close();
    } catch (_) {
      // A broken pipe / already-exited process must not skip the kill below.
    }
    if (process != null) await _terminateProcessTree(process);
    _closePending();
    _status = McpConnectionStatus.disconnected;
    _log('Disconnected');
  }

  void _log(String message) {
    if (message.isEmpty) return;
    _logs.add('${DateTime.now().toIso8601String()} ${_sanitize(message)}');
    if (_logs.length > 100) _logs.removeRange(0, _logs.length - 100);
  }

  static String _sanitize(
    String value, [
    Iterable<String> exactSecrets = const [],
  ]) {
    final headersRedacted = value.replaceAllMapped(
      RegExp(
        r'(authorization|cookie|set-cookie)\s*:\s*[^\r\n]+',
        caseSensitive: false,
      ),
      (match) => '${match.group(1)}: [REDACTED]',
    );
    var redacted = headersRedacted;
    for (final secret in exactSecrets) {
      if (secret.isNotEmpty) {
        redacted = redacted.replaceAll(secret, '[REDACTED]');
      }
    }
    return SecretScanner.redact(redacted);
  }

  static Future<void> _terminateProcessTree(Process process) async {
    final exitCode = process.exitCode;
    if (Platform.isWindows) {
      try {
        await Process.run(
          '${Platform.environment['SystemRoot'] ?? r'C:\Windows'}'
          r'\System32\taskkill.exe',
          ['/PID', '${process.pid}', '/T', '/F'],
        ).timeout(const Duration(seconds: 5));
      } catch (_) {
        process.kill(ProcessSignal.sigkill);
      }
    } else {
      process.kill(ProcessSignal.sigkill);
    }
    await exitCode.timeout(const Duration(seconds: 3), onTimeout: () => -1);
  }
}
