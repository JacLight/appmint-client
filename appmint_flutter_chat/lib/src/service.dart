import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'config.dart';
import 'models.dart';

/// The wire: one Socket.IO connection to `{endpoint}/chat`, authenticated from
/// the handshake (the server pushes `authenticate` back — never emit it).
///
/// Speaks exactly what the appmint React chat-client speaks, so the admin sees
/// the thread in the dashboard and in appmint_mobile without any server change:
///   send      → `chat-message` {message, chatId}         (no assistantId ⇒ human queue)
///   history   → `chat-history` {chatId, email}
///   typing    → `shareStatus`  {from, to, status:'typing', type:'typing'}
///   read      → `updateMessageStatus` {uid, status:'read', from, to}
///   listens   → message · queued · queue-update · agent-assigned · agent-changed
///               · chat-ended · status · update · token_expired
class AppmintChatService {
  AppmintChatService(this.config);
  final AppmintChatConfig config;

  io.Socket? _socket;
  AppmintChatConnection _state = AppmintChatConnection.disconnected;
  AppmintChatConnection get state => _state;
  bool get ready => _state == AppmintChatConnection.authenticated;

  final _connection = StreamController<AppmintChatConnection>.broadcast();
  final _auth = StreamController<AppmintAuthResult>.broadcast();
  final _messages = StreamController<AppmintChatMessage>.broadcast();
  final _queue = StreamController<AppmintQueueState>.broadcast();
  final _agent = StreamController<AppmintChatAgent>.broadcast();
  final _ended = StreamController<Map<String, dynamic>>.broadcast();
  final _transferred = StreamController<Map<String, dynamic>>.broadcast();
  final _notice = StreamController<String>.broadcast();
  final _status = StreamController<Map<String, dynamic>>.broadcast();
  final _update = StreamController<Map<String, dynamic>>.broadcast();
  final _errors = StreamController<String>.broadcast();
  final _stream = StreamController<Map<String, dynamic>>.broadcast();

  Stream<AppmintChatConnection> get onConnection => _connection.stream;
  Stream<AppmintAuthResult> get onAuth => _auth.stream;
  Stream<AppmintChatMessage> get onMessage => _messages.stream;
  Stream<AppmintQueueState> get onQueue => _queue.stream;
  Stream<AppmintChatAgent> get onAgent => _agent.stream;
  Stream<Map<String, dynamic>> get onEnded => _ended.stream;
  /// `chat-transferred` {chatId, fromAgent, note}.
  Stream<Map<String, dynamic>> get onTransferred => _transferred.stream;
  /// Session notices worth a line in the thread (expired, expiring).
  Stream<String> get onNotice => _notice.stream;
  /// Typing / presence relays (`shareStatus` echoes): {from, to, status|type}.
  Stream<Map<String, dynamic>> get onStatus => _status.stream;
  /// Read-receipt relays: {uid, status, from, to}.
  Stream<Map<String, dynamic>> get onUpdate => _update.stream;
  Stream<String> get onError => _errors.stream;
  /// AI replies stream in pieces: {chatId, messageId, event: chunk|tool-use|tool-result|end|error, data?, sk?}.
  Stream<Map<String, dynamic>> get onStream => _stream.stream;

  void _set(AppmintChatConnection s) {
    _state = s;
    _connection.add(s);
  }

  static Map<String, dynamic> _map(dynamic d) =>
      d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};

  /// Connect (or reconnect with a fresh token). Resolves once the server has
  /// answered `authenticate`; throws on a definite refusal.
  Future<AppmintAuthResult> connect() async {
    final token = await config.token();
    if (token == null || token.isEmpty) {
      _set(AppmintChatConnection.failed);
      throw StateError('Not signed in');
    }
    await _teardown();
    _set(AppmintChatConnection.connecting);
    String? sessionId;
    try {
      sessionId = await config.loadSessionId?.call();
    } catch (_) {
      sessionId = null;
    }

    final auth = <String, dynamic>{
      'token': token,
      'orgId': config.orgId,
      if (config.configId != null) 'configId': config.configId,
      if (config.deviceId != null) 'deviceId': config.deviceId,
      if (config.appId != null) 'appId': config.appId,
      'context': {
        'device': 'mobile',
        'language': config.language,
        if (config.appId != null) 'appId': config.appId,
        if (config.configId != null) 'configId': config.configId,
        if (config.deviceId != null) 'deviceId': config.deviceId,
        'currentUrl': 'app://${config.appId ?? 'app'}/support',
        if (sessionId != null && sessionId.isNotEmpty) 'chatSessionId': sessionId,
      },
    };
    final s = io.io(
      '${config.endpoint}/chat',
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth(auth)
          .disableAutoConnect()
          .enableReconnection()
          .setReconnectionDelay(2000)
          .setReconnectionDelayMax(10000)
          .setReconnectionAttempts(10)
          .build(),
    );
    _socket = s;
    final first = Completer<AppmintAuthResult>();

    s.onConnect((_) => _set(AppmintChatConnection.connected));
    s.onDisconnect((_) => _set(AppmintChatConnection.disconnected));
    s.onConnectError((e) {
      _errors.add('connect_error: $e');
      if (!first.isCompleted) first.completeError(StateError('Could not reach chat: $e'));
    });
    s.on('authenticate', (d) {
      final r = AppmintAuthResult.fromJson(_map(d));
      _set(r.success ? AppmintChatConnection.authenticated : AppmintChatConnection.failed);
      if (r.success && (r.chatSessionId ?? '').isNotEmpty) {
        config.saveSessionId?.call(r.chatSessionId!).catchError((_) {});
      }
      _auth.add(r);
      if (!first.isCompleted) first.complete(r);
    });
    s.on('message', (d) => _messages.add(AppmintChatMessage.fromJson(_map(d))));
    s.on('queued', (d) => _queue.add(AppmintQueueState.fromJson(_map(d))));
    s.on('queue-update', (d) => _queue.add(AppmintQueueState.fromJson(_map(d))));
    s.on('agent-assigned', (d) {
      final m = _map(d);
      final a = m['agent'];
      if (a is Map) _agent.add(AppmintChatAgent.fromJson(Map<String, dynamic>.from(a)));
    });
    s.on('agent-changed', (d) {
      final m = _map(d);
      final email = m['newAgent']?.toString();
      if (email != null && email.isNotEmpty) {
        _agent.add(AppmintChatAgent(email: email, name: (m['newAgentName'] ?? email).toString()));
      }
    });
    s.on('chat-ended', (d) => _ended.add(_map(d)));
    s.on('chat-transferred', (d) => _transferred.add(_map(d)));
    s.on('session-expired', (_) => _notice.add('Your session has expired. Please start a new conversation.'));
    s.on('chat-stream', (d) => _stream.add(_map(d)));
    s.on('status', (d) => _status.add(_map(d)));
    s.on('update', (d) => _update.add(_map(d)));
    s.on('token_expired', (_) async {
      _errors.add('token_expired');
      _set(AppmintChatConnection.failed);
      await config.onTokenExpired?.call();
    });
    s.on('error', (d) => _errors.add(d.toString()));
    s.connect();

    return first.future.timeout(const Duration(seconds: 15), onTimeout: () {
      _set(AppmintChatConnection.failed);
      throw TimeoutException('Chat did not answer');
    });
  }

  /// Guarantees room membership after a reconnect. Idempotent.
  void joinChat(String chatId) => _socket?.emit('join-chat', {'chatId': chatId});

  Future<Map<String, dynamic>> _ack(String event, Map<String, dynamic> body,
      {Duration timeout = const Duration(seconds: 12)}) {
    final c = Completer<Map<String, dynamic>>();
    final s = _socket;
    if (s == null || !s.connected) {
      return Future.error(StateError('Chat is not connected'));
    }
    s.emitWithAck(event, body, ack: (d) {
      if (!c.isCompleted) c.complete(_map(d));
    });
    return c.future.timeout(timeout, onTimeout: () => throw TimeoutException('$event timed out'));
  }

  /// The thread so far, oldest first. (The server strips attachments from
  /// history; live messages carry them.)
  Future<List<AppmintChatMessage>> history(String chatId, {String? email}) async {
    final r = await _ack('chat-history', {'chatId': chatId, if (email != null) 'email': email});
    if (r['success'] != true) throw StateError((r['error'] ?? 'Could not load history').toString());
    final list = (r['history'] as List?) ?? const [];
    return list
        .whereType<Map>()
        .map((m) => AppmintChatMessage.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }

  /// Send text (and optional uploaded files). Where it goes is the SERVER's
  /// call: with a `configId` the config's AI answers (streamed over
  /// `chat-stream`) and hands off to a person when the conversation calls for
  /// it; without one, or once a person is on the thread, it goes to them. Ack:
  /// {success, messageId, chatId, routedTo: 'queued' | 'agent'}.
  Future<Map<String, dynamic>> send(String chatId, String text, {List<Map<String, dynamic>>? files}) async {
    final r = await _ack('chat-message', {
      'message': text,
      'chatId': chatId,
      if (files != null && files.isNotEmpty) 'files': files,
    });
    if (r['success'] != true) throw StateError((r['error'] ?? r['message'] ?? 'Not sent').toString());
    return r;
  }

  /// Typing indicator to the assigned admin. React sends `status`, the Flutter
  /// admin reads `type` — send both so every console shows it.
  void typing({required String from, required String to, bool isTyping = true}) {
    _socket?.emit('shareStatus', {
      'from': from,
      'to': to,
      'status': isTyping ? 'typing' : 'idle',
      'type': isTyping ? 'typing' : 'idle',
      'sentTime': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Read receipt for a message the customer has seen. `uid` is the message's
  /// server id (sk), never a local id.
  void markRead({required String uid, required String from, required String to}) {
    _socket?.emit('updateMessageStatus', {'uid': uid, 'status': 'read', 'from': from, 'to': to});
  }

  /// Upload files for the thread: `POST {endpoint}/chat/upload/{scope}/{email}`
  /// (multipart `files`) → `[{name, url, path}]`. The url is a signed link;
  /// `path` is the durable reference. Same call the web widget makes.
  Future<List<Map<String, dynamic>>> upload(String chatId, List<AppmintChatAttachment> files) async {
    final token = await config.token();
    final scope = config.configId ?? chatId;
    final uri = Uri.parse('${config.endpoint}/chat/upload/${Uri.encodeComponent(scope)}/${Uri.encodeComponent(config.user.email)}');
    final req = http.MultipartRequest('POST', uri)
      ..headers['orgid'] = config.orgId
      ..headers['Accept'] = 'application/json';
    if (config.appId != null) req.headers['appId'] = config.appId!;
    if (token != null && token.isNotEmpty) req.headers['Authorization'] = 'Bearer $token';
    for (final f in files) {
      req.files.add(http.MultipartFile.fromBytes('files', f.bytes, filename: f.name));
    }
    final res = await http.Response.fromStream(await req.send().timeout(const Duration(seconds: 60)));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw StateError('Upload failed (${res.statusCode})');
    }
    final body = jsonDecode(res.body);
    final list = body is List ? body : (body is Map && body['data'] is List ? body['data'] : const []);
    final out = <Map<String, dynamic>>[];
    for (var i = 0; i < list.length; i++) {
      final m = list[i] is Map ? Map<String, dynamic>.from(list[i]) : <String, dynamic>{};
      if (i < files.length) m['mimeType'] = files[i].mimeType;
      out.add(m);
    }
    return out;
  }

  Future<Map<String, dynamic>> close(String chatId, {String reason = 'customer_closed', bool sendTranscript = false, String? transcriptEmail}) {
    return _ack('close-chat', {
      'chatId': chatId,
      'reason': reason,
      'sendTranscript': sendTranscript,
      if (transcriptEmail != null) 'transcriptEmail': transcriptEmail,
    });
  }

  Future<void> _teardown() async {
    final s = _socket;
    _socket = null;
    if (s != null) {
      try {
        s.dispose();
      } catch (e) {
        if (kDebugMode) debugPrint('appmint_chat teardown: $e');
      }
    }
  }

  Future<void> dispose() async {
    await _teardown();
    _set(AppmintChatConnection.disconnected);
    for (final c in [_connection, _auth, _messages, _queue, _agent, _ended, _status, _update, _errors, _stream, _transferred, _notice]) {
      await c.close();
    }
  }
}
