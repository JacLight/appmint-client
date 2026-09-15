/// One message in the customer ↔ admin thread.
///
/// The gateway sends every live message in BOTH a flat and a nested (`data`)
/// shape, and history comes back flat with ISO timestamps — this parser takes
/// all of them.
class AppmintChatMessage {
  final String id;
  final String chatId;
  final String from;
  final String to;
  final String content;
  /// `user` | `system` | `ai-assistant`
  final String type;
  final String status; // pending | sent | delivered | read
  final DateTime sentAt;
  final List<Map<String, dynamic>> files;
  final String? senderRole; // customer | agent | system

  const AppmintChatMessage({
    required this.id,
    required this.chatId,
    required this.from,
    required this.to,
    required this.content,
    this.type = 'user',
    this.status = 'sent',
    required this.sentAt,
    this.files = const [],
    this.senderRole,
  });

  bool get isSystem => type == 'system' || from == 'system';
  bool get isAi => type == 'ai-assistant';
  bool mine(String myEmail) => from.toLowerCase() == myEmail.toLowerCase();

  AppmintChatMessage copyWith({String? id, String? status}) => AppmintChatMessage(
        id: id ?? this.id,
        chatId: chatId,
        from: from,
        to: to,
        content: content,
        type: type,
        status: status ?? this.status,
        sentAt: sentAt,
        files: files,
        senderRole: senderRole,
      );

  static DateTime _when(dynamic v) {
    if (v == null) return DateTime.now();
    if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt()).toLocal();
    final s = v.toString();
    final n = int.tryParse(s);
    if (n != null) return DateTime.fromMillisecondsSinceEpoch(n).toLocal();
    return DateTime.tryParse(s)?.toLocal() ?? DateTime.now();
  }

  static String _text(dynamic c) {
    if (c == null) return '';
    if (c is String) return c;
    if (c is Map) {
      // Rich content from the admin console: { text } or a Quill delta.
      final t = c['text'] ?? c['content'] ?? c['message'];
      if (t is String) return t;
      final ops = c['ops'];
      if (ops is List) {
        return ops.map((o) => o is Map ? (o['insert'] ?? '').toString() : '').join().trim();
      }
    }
    return c.toString();
  }

  factory AppmintChatMessage.fromJson(Map<String, dynamic> json) {
    final data = json['data'] is Map ? Map<String, dynamic>.from(json['data']) : json;
    return AppmintChatMessage(
      id: (json['messageId'] ?? json['sk'] ?? json['id'] ?? data['uuid'] ?? data['id'] ?? '').toString(),
      chatId: (data['chatId'] ?? json['chatId'] ?? '').toString(),
      from: (data['from'] ?? '').toString(),
      to: (data['to'] ?? '').toString(),
      content: _text(data['content'] ?? data['message']),
      type: (data['type'] ?? 'user').toString(),
      status: (data['status'] ?? 'sent').toString(),
      sentAt: _when(data['sentTime'] ?? data['timestamp'] ?? json['createdate']),
      files: (data['files'] is List)
          ? (data['files'] as List).whereType<Map>().map((f) => Map<String, dynamic>.from(f)).toList()
          : const [],
      senderRole: data['senderRole']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'chatId': chatId,
        'from': from,
        'to': to,
        'content': content,
        'type': type,
        'status': status,
        'sentTime': sentAt.toUtc().toIso8601String(),
        'files': files,
        if (senderRole != null) 'senderRole': senderRole,
      };
}

/// A file the customer picked, before upload.
class AppmintChatAttachment {
  final List<int> bytes;
  final String name;
  final String mimeType;
  const AppmintChatAttachment({required this.bytes, required this.name, required this.mimeType});
  bool get isImage => mimeType.startsWith('image/');
}

/// Is this uploaded/received file an image? By mime type, else by extension.
bool appmintFileIsImage(Map<String, dynamic> f) {
  final mime = (f['mimeType'] ?? f['type'] ?? '').toString().toLowerCase();
  if (mime.startsWith('image/')) return true;
  final name = (f['name'] ?? f['url'] ?? f['path'] ?? '').toString().toLowerCase().split('?').first;
  return RegExp(r'\.(png|jpe?g|gif|webp|heic|bmp)$').hasMatch(name);
}

/// The admin currently handling the chat.
class AppmintChatAgent {
  final String email;
  final String name;
  const AppmintChatAgent({required this.email, required this.name});
  factory AppmintChatAgent.fromJson(Map<String, dynamic> j) {
    final email = (j['email'] ?? '').toString();
    final name = (j['name'] ?? '').toString().trim();
    return AppmintChatAgent(email: email, name: name.isNotEmpty ? name : _fromEmail(email));
  }

  /// "jane" from jane@x.com — what to call an admin whose profile has no name.
  /// An agent known only by email (e.g. inferred from history).
  factory AppmintChatAgent.fromEmail(String email) => AppmintChatAgent(email: email, name: _fromEmail(email));

  static String _fromEmail(String email) {
    final local = email.split('@').first;
    return local.isEmpty ? 'Agent' : local[0].toUpperCase() + local.substring(1);
  }
}

/// Where the customer stands in the support queue.
class AppmintQueueState {
  final int position;
  final int ahead;
  final int? estimatedWaitSeconds;
  final String? message;
  const AppmintQueueState({required this.position, required this.ahead, this.estimatedWaitSeconds, this.message});
  factory AppmintQueueState.fromJson(Map<String, dynamic> j) => AppmintQueueState(
        position: (j['position'] as num?)?.toInt() ?? 0,
        ahead: (j['ahead'] as num?)?.toInt() ?? 0,
        estimatedWaitSeconds: (j['estimatedWaitSeconds'] as num?)?.toInt(),
        message: j['message']?.toString(),
      );
}

/// Result of the handshake `authenticate` push.
class AppmintAuthResult {
  final bool success;
  final String? error;
  final String? message;
  final String? email;
  final String? name;
  final String? role;
  final String? chatSessionId;
  final Map<String, dynamic>? config;
  const AppmintAuthResult({
    required this.success,
    this.error,
    this.message,
    this.email,
    this.name,
    this.role,
    this.chatSessionId,
    this.config,
  });
  factory AppmintAuthResult.fromJson(Map<String, dynamic> j) {
    final u = j['user'] is Map ? Map<String, dynamic>.from(j['user']) : const <String, dynamic>{};
    return AppmintAuthResult(
      success: j['success'] == true,
      error: j['error']?.toString(),
      message: j['message']?.toString(),
      email: u['email']?.toString(),
      name: u['name']?.toString(),
      role: u['role']?.toString(),
      chatSessionId: j['chatSessionId']?.toString(),
      config: j['config'] is Map ? Map<String, dynamic>.from(j['config']) : null,
    );
  }
}

enum AppmintChatConnection { disconnected, connecting, connected, authenticated, failed }
