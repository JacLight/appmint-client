import 'dart:async';
import 'package:flutter/foundation.dart';
import 'config.dart';
import 'models.dart';
import 'service.dart';

/// Screen state for one customer ↔ admin thread. Owns the [AppmintChatService].
///
/// The thread id for a signed-in customer is fixed by the gateway:
/// `customer::{email}` — nothing to create, it exists the moment they write.
class AppmintChatController extends ChangeNotifier {
  AppmintChatController(this.config) : service = AppmintChatService(config);

  final AppmintChatConfig config;
  final AppmintChatService service;

  final List<AppmintChatMessage> messages = [];
  AppmintChatConnection connection = AppmintChatConnection.disconnected;
  bool loadingHistory = false;
  String? error;
  AppmintChatAgent? agent;
  AppmintQueueState? queue;
  bool ended = false;
  String? endedReason;
  bool peerTyping = false;
  String myEmail = '';
  String chatId = '';

  final List<StreamSubscription> _subs = [];
  Timer? _typingClear;
  DateTime? _lastTypingSent;
  bool _disposed = false;
  bool _refreshed = false;

  /// Who is on the other side, for the header.
  String get counterpartName => (agent?.name.trim().isNotEmpty ?? false) ? agent!.name : config.supportName;
  bool get canSend => connection == AppmintChatConnection.authenticated;

  Future<void> start() async {
    myEmail = config.user.email.trim().toLowerCase();
    chatId = 'customer::$myEmail';
    error = null;
    _listen();
    try {
      final auth = await service.connect();
      if (_disposed) return;
      if (!auth.success) {
        // A stale token: let the app refresh it, then try once more with the new one.
        if (auth.error == 'token_expired' && config.onTokenExpired != null && !_refreshed) {
          _refreshed = true;
          await config.onTokenExpired!.call();
          if (_disposed) return;
          return start();
        }
        error = auth.message ?? auth.error ?? 'Could not sign in to chat';
        notifyListeners();
        return;
      }
      _refreshed = false;
      if ((auth.email ?? '').isNotEmpty) {
        myEmail = auth.email!.toLowerCase();
        chatId = 'customer::$myEmail';
      }
      service.joinChat(chatId);
      await _loadHistory();
    } catch (e) {
      if (_disposed) return;
      error = e.toString().replaceFirst('Bad state: ', '').replaceFirst('StateError: ', '');
      notifyListeners();
    }
  }

  Future<void> retry() => start();

  void _listen() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _subs.add(service.onConnection.listen((s) {
      connection = s;
      if (s == AppmintChatConnection.authenticated && chatId.isNotEmpty) service.joinChat(chatId);
      notifyListeners();
    }));
    _subs.add(service.onMessage.listen(_incoming));
    _subs.add(service.onQueue.listen((q) {
      queue = q;
      aiTyping = false;
      // `queued` carries the server's own words ("You're #2 in line…"); the
      // 15-second `queue-update`s only move the banner.
      if ((q.message ?? '').isNotEmpty) _systemLine('queued', q.message!);
      notifyListeners();
    }));
    _subs.add(service.onAgent.listen((a) {
      final hadAgent = agent != null;
      final changed = agent?.email != a.email;
      agent = a;
      queue = null;
      ended = false;
      aiTyping = false;
      // When an agent picks the chat up the gateway already sends a system
      // message ("X has joined the chat."); adding our own line here put the
      // same news in the thread twice. Only a change of agent needs a line.
      if (changed && hadAgent) _systemLine('assigned', 'Now talking to ${a.name}');
      notifyListeners();
    }));
    _subs.add(service.onTransferred.listen((t) {
      final from = (t['fromAgent'] ?? 'Previous agent').toString();
      final note = (t['note'] ?? '').toString();
      _systemLine('transfer', 'Chat transferred from $from${note.isNotEmpty ? ': $note' : ''}');
      notifyListeners();
    }));
    _subs.add(service.onEnded.listen((e) {
      ended = true;
      endedReason = e['reason']?.toString();
      peerTyping = false;
      aiTyping = false;
      queue = null;
      _systemLine('ended', endedReason == 'agent' ? 'The agent has ended this chat.' : 'This chat has ended.');
      notifyListeners();
    }));
    _subs.add(service.onNotice.listen((text) {
      _systemLine('notice', text);
      notifyListeners();
    }));
    _subs.add(service.onStatus.listen((s) {
      final from = (s['from'] ?? '').toString().toLowerCase();
      if (from.isEmpty || from == myEmail) return;
      final kind = (s['status'] ?? s['type'] ?? '').toString();
      peerTyping = kind == 'typing';
      _typingClear?.cancel();
      if (peerTyping) {
        _typingClear = Timer(const Duration(seconds: 4), () {
          peerTyping = false;
          if (!_disposed) notifyListeners();
        });
      }
      notifyListeners();
    }));
    _subs.add(service.onUpdate.listen((u) {
      final uid = (u['uid'] ?? '').toString();
      final status = (u['status'] ?? '').toString();
      if (uid.isEmpty || status.isEmpty) return;
      final i = messages.indexWhere((m) => m.id == uid);
      if (i >= 0) {
        messages[i] = messages[i].copyWith(status: status);
        notifyListeners();
      }
    }));
    _subs.add(service.onStream.listen(_streamed));
    _subs.add(service.onError.listen((e) {
      if (e == 'token_expired') {
        error = 'Session expired — sign in again.';
        notifyListeners();
      }
    }));
  }

  Future<void> _loadHistory() async {
    loadingHistory = true;
    notifyListeners();
    try {
      final h = await service.history(chatId, email: myEmail);
      messages
        ..clear()
        ..addAll(h.where((m) => m.content.isNotEmpty || m.files.isNotEmpty));
      // The admin who last wrote is the one handling this thread.
      for (final m in messages.reversed) {
        if (!m.isSystem && !m.isAi && !m.mine(myEmail) && m.from.contains('@')) {
          agent ??= AppmintChatAgent.fromEmail(m.from);
          break;
        }
      }
    } catch (e) {
      error ??= 'Could not load earlier messages';
    }
    loadingHistory = false;
    notifyListeners();
  }

  void _incoming(AppmintChatMessage m) {
    if (m.chatId.isNotEmpty && m.chatId != chatId) return;
    if (m.id.isNotEmpty && messages.any((x) => x.id == m.id)) return;
    if (m.isAi && messages.any((x) => x.isAi && x.content == m.content)) return;
    if (m.isSystem && messages.isNotEmpty && messages.last.isSystem && messages.last.content == m.content) return;
    if (m.mine(myEmail)) {
      // Our own echo — reconcile an optimistic bubble instead of duplicating it.
      final i = messages.indexWhere((x) => x.id.startsWith('local-') && x.content == m.content && x.files.length == m.files.length);
      if (i >= 0) {
        messages[i] = m.copyWith(status: 'delivered');
        notifyListeners();
        return;
      }
    }
    messages.add(m);
    if (!m.mine(myEmail) && !m.isSystem) {
      peerTyping = false;
      _typingClear?.cancel();
      if (!m.isAi && m.from.contains('@') && agent?.email != m.from) {
        agent = agent?.email == m.from ? agent : AppmintChatAgent.fromEmail(m.from);
      }
      queue = null;
      if (m.id.isNotEmpty && m.status != 'read') {
        service.markRead(uid: m.id, from: m.from, to: myEmail);
      }
    }
    notifyListeners();
  }

  /// A status line in the thread — what the widget shows for the same event.
  /// Same text twice in a row is dropped (the server may echo it as a message).
  void _systemLine(String kind, String text) {
    if (messages.isNotEmpty && messages.last.isSystem && messages.last.content == text) return;
    messages.add(AppmintChatMessage(
      id: 'system-$kind-${DateTime.now().microsecondsSinceEpoch}', chatId: chatId, from: 'system', to: myEmail,
      content: text, type: 'system', status: 'sent', sentAt: DateTime.now(), senderRole: 'system',
    ));
  }

  /// One AI reply arrives as many `chunk`s under one `messageId`; show it as a
  /// single bubble that grows, and settle its id on `end`.
  bool aiTyping = false;
  void _streamed(Map<String, dynamic> e) {
    final cid = (e['chatId'] ?? '').toString();
    if (cid.isNotEmpty && cid != chatId) return;
    final mid = (e['messageId'] ?? '').toString();
    if (mid.isEmpty) return;
    final event = (e['event'] ?? '').toString();
    // The server streams the reply under the CUSTOMER message's id, so the AI
    // bubble gets its own id — otherwise the answer would grow inside the question.
    final aiId = 'ai-$mid';
    final i = messages.indexWhere((m) => m.id == aiId);
    switch (event) {
      case 'chunk':
        final text = (e['data'] ?? '').toString();
        if (i >= 0) {
          final m = messages[i];
          messages[i] = AppmintChatMessage(
            id: m.id, chatId: m.chatId, from: m.from, to: m.to, content: m.content + text,
            type: m.type, status: m.status, sentAt: m.sentAt, senderRole: m.senderRole,
          );
        } else {
          messages.add(AppmintChatMessage(
            id: aiId, chatId: chatId, from: 'assistant', to: myEmail, content: text,
            type: 'ai-assistant', status: 'sent', sentAt: DateTime.now(), senderRole: 'agent',
          ));
        }
        aiTyping = true;
        peerTyping = false;
        break;
      case 'tool-use':
        // The AI explains a hand-off in its own words (streamed next), like the web widget.
        aiTyping = true;
        break;
      case 'end':
        aiTyping = false;
        final sk = (e['sk'] ?? '').toString();
        if (i >= 0) {
          if (messages[i].content.trim().isEmpty) {
            messages.removeAt(i);
          } else if (sk.isNotEmpty && sk != mid) {
            messages[i] = messages[i].copyWith(id: sk, status: 'delivered');
          }
        }
        break;
      case 'error':
        aiTyping = false;
        if (i >= 0 && messages[i].content.trim().isEmpty) messages.removeAt(i);
        error = (e['error'] ?? 'The assistant could not answer').toString();
        break;
      default:
        return;
    }
    notifyListeners();
  }

  Future<void> send(String text, {List<Map<String, dynamic>>? files}) async {
    final t = text.trim();
    if (t.isEmpty && (files == null || files.isEmpty)) return;
    final local = AppmintChatMessage(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      chatId: chatId,
      from: myEmail,
      to: agent?.email ?? 'queued',
      content: t,
      status: 'pending',
      sentAt: DateTime.now(),
      files: files ?? const [],
      senderRole: 'customer',
    );
    messages.add(local);
    ended = false;
    error = null;
    notifyListeners();
    try {
      final ack = await service.send(chatId, t, files: files);
      final i = messages.indexWhere((m) => m.id == local.id);
      if (i >= 0) {
        messages[i] = local.copyWith(id: (ack['messageId'] ?? local.id).toString(), status: 'sent');
      }
    } catch (e) {
      final i = messages.indexWhere((m) => m.id == local.id);
      if (i >= 0) messages[i] = local.copyWith(status: 'failed');
      error = e.toString().replaceFirst('Bad state: ', '');
    }
    notifyListeners();
  }

  /// Upload the picked files, then send them (with optional text) on one
  /// message. The bubble shows the local bytes until the upload settles.
  Future<void> sendAttachments(List<AppmintChatAttachment> files, {String text = ''}) async {
    if (files.isEmpty) return send(text);
    final localId = 'local-${DateTime.now().microsecondsSinceEpoch}';
    final preview = files
        .map((f) => <String, dynamic>{'name': f.name, 'mimeType': f.mimeType, 'bytes': f.bytes})
        .toList();
    messages.add(AppmintChatMessage(
      id: localId, chatId: chatId, from: myEmail, to: agent?.email ?? 'queued', content: text.trim(),
      status: 'pending', sentAt: DateTime.now(), files: preview, senderRole: 'customer',
    ));
    ended = false;
    error = null;
    notifyListeners();
    try {
      final uploaded = await service.upload(chatId, files);
      final ack = await service.send(chatId, text.trim(), files: uploaded);
      final i = messages.indexWhere((m) => m.id == localId);
      if (i >= 0) {
        final m = messages[i];
        messages[i] = AppmintChatMessage(
          id: (ack['messageId'] ?? localId).toString(), chatId: m.chatId, from: m.from, to: m.to, content: m.content,
          status: 'sent', sentAt: m.sentAt, files: uploaded, senderRole: m.senderRole,
        );
      }
    } catch (e) {
      final i = messages.indexWhere((m) => m.id == localId);
      if (i >= 0) messages[i] = messages[i].copyWith(status: 'failed');
      error = e.toString().replaceFirst('Bad state: ', '');
    }
    notifyListeners();
  }

  /// Throttled typing signal — only meaningful once an admin is on the thread.
  void typing(bool isTyping) {
    final to = agent?.email;
    if (to == null || !canSend) return;
    final now = DateTime.now();
    if (isTyping && _lastTypingSent != null && now.difference(_lastTypingSent!).inSeconds < 2) return;
    _lastTypingSent = isTyping ? now : null;
    service.typing(from: myEmail, to: to, isTyping: isTyping);
  }

  @override
  void dispose() {
    _disposed = true;
    _typingClear?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    service.dispose();
    super.dispose();
  }
}
