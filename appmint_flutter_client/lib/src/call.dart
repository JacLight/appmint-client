/// One request the client made, for showing a developer what just happened.
///
/// Carries no token values — only whether each was attached, which is the part
/// that is actually confusing about this API.
class AppmintCall {
  final String method;
  final String path;
  final int status;
  final Duration took;

  /// Whether the app had authenticated itself by the time this went out.
  final bool appAuthenticated;

  /// Whether a signed-in person's token rode along in `x-client-authorization`.
  final bool sentUserToken;

  final DateTime at;

  const AppmintCall({
    required this.method,
    required this.path,
    required this.status,
    required this.took,
    required this.appAuthenticated,
    required this.sentUserToken,
    required this.at,
  });

  bool get ok => status >= 200 && status < 300;

  @override
  String toString() => '$method $path → $status (${took.inMilliseconds}ms)';
}
