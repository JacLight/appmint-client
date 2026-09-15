/// Who is chatting — the signed-in customer as the app knows them.
class AppmintChatUser {
  final String email;
  final String? name;
  const AppmintChatUser({required this.email, this.name});
}

/// Everything the chat needs from the host app. Pure data + one callback.
class AppmintChatConfig {
  /// appengine base URL, e.g. `https://appengine.appmint.io` (no trailing slash).
  final String endpoint;

  /// The org the customer belongs to (`orgid` header value).
  final String orgId;

  /// The signed-in customer.
  final AppmintChatUser user;

  /// Returns the CUSTOMER's JWT (the one sent as `x-client-authorization`),
  /// never the app token. Called on every (re)connect so a refreshed token is
  /// picked up.
  final Future<String?> Function() token;

  /// Optional `chat_config` id. With one, only that config's agents are alerted
  /// and its AI (if any) answers first. Without one every online admin is
  /// alerted and no AI is involved — plain "talk to support".
  final String? configId;

  /// Stable per-install id (enables the admin's `engage` nudges). Optional.
  final String? deviceId;

  /// Which app this is (the widget's `appId`). Comes from the site; omitted when unset.
  final String? appId;

  /// UI language sent in the handshake context.
  final String language;

  /// Shown to the customer as the other party until an admin joins.
  final String supportName;

  /// First line the customer sees in an empty chat.
  final String welcome;

  /// Session id persistence. The gateway hands a `chatSessionId` back on
  /// authenticate; send it on the next connect to RESUME the thread (no new
  /// greeting, same context). Without these the AI greets on every open.
  final Future<String?> Function()? loadSessionId;
  final Future<void> Function(String id)? saveSessionId;

  /// Called when the server rejects the token; the app refreshes and the
  /// controller reconnects with a fresh `token()`.
  final Future<void> Function()? onTokenExpired;

  const AppmintChatConfig({
    required this.endpoint,
    required this.orgId,
    required this.user,
    required this.token,
    this.configId,
    this.deviceId,
    this.appId,
    this.language = 'en',
    this.supportName = 'Support',
    this.welcome = 'How can we help? Someone from the team will reply here.',
    this.onTokenExpired,
    this.loadSessionId,
    this.saveSessionId,
  });
}

/// The chat settings an appmint SITE record carries (`data.chatConfig`,
/// `data.chatAppId`). Apps load their site by name and pass these in, so the
/// admin changes the config in one place and every app follows.
class AppmintSiteChat {
  final String? configId;
  final String? appId;
  const AppmintSiteChat({this.configId, this.appId});

  factory AppmintSiteChat.fromSite(Map<String, dynamic>? site) {
    final d = site == null ? const <String, dynamic>{} : (site['data'] is Map ? Map<String, dynamic>.from(site['data']) : site);
    String? str(dynamic v) => v == null || v.toString().trim().isEmpty ? null : v.toString().trim();
    return AppmintSiteChat(configId: str(d['configId'] ?? d['chatConfig']), appId: str(d['appId'] ?? d['chatAppId']));
  }
}
