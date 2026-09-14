/// Anything the client refuses to do, or the server refused to do.
///
/// [message] is safe to show a person: appengine writes its refusals in plain
/// language ("That code is not right. Check the code and try again.") and this
/// client passes them through rather than replacing them with its own wording.
class AppmintException implements Exception {
  final String message;

  /// HTTP status, when the failure came from a response at all.
  final int? statusCode;

  /// The server's machine-readable reason, where it gives one — for example
  /// `invalid_code` versus `challenge_expired`, which need different cures.
  final String? reason;

  /// The undecoded response body, for logging a shape this client did not
  /// expect. Never show it to a person.
  final String? body;

  const AppmintException(
    this.message, {
    this.statusCode,
    this.reason,
    this.body,
  });

  @override
  String toString() => message;
}

/// The app itself could not authenticate, so no request can be made at all.
/// Wrong `appId`/`key`/`secret`, or the organization does not exist.
class AppmintAppAuthException extends AppmintException {
  const AppmintAppAuthException(super.message, {super.statusCode, super.body});
}

/// The signed-in session is gone and cannot be renewed. Send the person back
/// to sign-in; retrying will not help.
class AppmintSessionExpiredException extends AppmintException {
  const AppmintSessionExpiredException([
    super.message = 'Session expired. Please sign in again.',
  ]) : super(statusCode: 401);
}

/// The request never reached the server — no response was ever received.
/// Distinct from a 5xx, which means the server answered and failed.
class AppmintNetworkException extends AppmintException {
  const AppmintNetworkException(super.message);
}
