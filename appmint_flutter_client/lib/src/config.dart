/// Everything the client needs to reach one Appmint organization.
///
/// The app credentials identify *the application* to appengine. They are not a
/// secret in a mobile binary — anyone can read them out of an APK or an IPA —
/// so treat them as an identifier, never as a security boundary. What protects
/// a request is the signed-in person's token, which the server issues and this
/// client attaches separately.
class AppmintConfig {
  /// Where appengine lives, with scheme and no trailing slash.
  /// e.g. `https://appengine.appmint.io`
  final String baseUrl;

  /// The organization every request is scoped to. Sent as `orgid` on
  /// everything; there is no such thing as an org-less call.
  final String orgId;

  final String appId;
  final String appKey;
  final String appSecret;

  /// Ask the server to resolve the organization from the request's domain
  /// rather than the header. Only for deployments that serve several orgs from
  /// separate hostnames.
  final bool domainAsOrg;

  /// How long any single request may take before it is abandoned.
  final Duration timeout;

  /// Attempts made when a request never reaches the server — connection
  /// refused, host lookup failed, timed out. A real HTTP response, including a
  /// 500, is never retried: the server answered, and repeating the call would
  /// only repeat the answer.
  final int transientRetries;

  /// Print each request, its outcome and the server's error text. Leave on in
  /// debug builds; it is the fastest way to see a wrong header or a wrong org.
  final bool logRequests;

  const AppmintConfig({
    required this.baseUrl,
    required this.orgId,
    required this.appId,
    required this.appKey,
    required this.appSecret,
    this.domainAsOrg = false,
    this.timeout = const Duration(seconds: 30),
    this.transientRetries = 4,
    this.logRequests = false,
  });

  AppmintConfig copyWith({
    String? baseUrl,
    String? orgId,
    String? appId,
    String? appKey,
    String? appSecret,
    bool? domainAsOrg,
    Duration? timeout,
    int? transientRetries,
    bool? logRequests,
  }) {
    return AppmintConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      orgId: orgId ?? this.orgId,
      appId: appId ?? this.appId,
      appKey: appKey ?? this.appKey,
      appSecret: appSecret ?? this.appSecret,
      domainAsOrg: domainAsOrg ?? this.domainAsOrg,
      timeout: timeout ?? this.timeout,
      transientRetries: transientRetries ?? this.transientRetries,
      logRequests: logRequests ?? this.logRequests,
    );
  }
}
