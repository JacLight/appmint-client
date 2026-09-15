import '../errors.dart';

/// Which kind of person is signing in.
///
/// These are two different records on the server with two different sign-in
/// routes, and they are not interchangeable: a staff account is not a thin
/// customer, and some routes behave differently for each. The distinction is
/// kept visible rather than hidden behind one `signIn`, because hiding it turns
/// a real difference into a mystery.
enum Identity {
  /// Employees, managers, administrators. Signs in at `/profile/user/signin`.
  staff,

  /// The people an organization serves — guests, buyers, attendees.
  /// Signs in at `/profile/customer/signin`.
  customer;

  String get signInPath =>
      this == Identity.staff ? '/profile/user/signin' : '/profile/customer/signin';

  String get signUpPath =>
      this == Identity.staff ? '/profile/user/signup' : '/profile/customer/signup';

  String get magicCodePath =>
      this == Identity.staff ? '/profile/user/magic-link' : '/profile/magic-link';

  String get magicVerifyPath => this == Identity.staff
      ? '/profile/user/magic-link/redirect'
      : '/profile/magic-link/redirect';
}

/// How a verification code reaches the person.
enum VerificationMethod {
  email,
  sms,
  authenticator;

  static VerificationMethod parse(String? raw) => switch (raw) {
        'sms' => VerificationMethod.sms,
        'authenticator' => VerificationMethod.authenticator,
        _ => VerificationMethod.email,
      };

  /// An authenticator code is computed on the person's own device. There is
  /// nothing to send, so offering "send it again" would be a lie.
  bool get canResend => this != VerificationMethod.authenticator;

  String get wireName => name;
}

/// Whoever is signed in.
class AppmintUser {
  /// The record id (`sk` on the server).
  final String id;
  final String email;
  final String? name;
  final String? phone;
  final String? avatar;
  final Identity identity;

  /// The untouched record, for fields this class does not name.
  final Map<String, dynamic> raw;

  const AppmintUser({
    required this.id,
    required this.email,
    required this.identity,
    required this.raw,
    this.name,
    this.phone,
    this.avatar,
  });

  factory AppmintUser.fromJson(Map<String, dynamic> json, Identity identity) {
    final data = json['data'] is Map
        ? Map<String, dynamic>.from(json['data'] as Map)
        : json;

    final first = _str(data['firstName']);
    final last = _str(data['lastName']);
    final assembled = [first, last].where((s) => s != null && s.isNotEmpty).join(' ');

    return AppmintUser(
      id: (json['sk'] ?? json['id'] ?? data['id'] ?? '').toString(),
      email: (data['email'] ?? data['username'] ?? '').toString(),
      name: _str(data['name']) ?? (assembled.isNotEmpty ? assembled : null),
      phone: _str(data['phone']),
      avatar: _str(data['portrait']) ?? _str(data['avatar']),
      identity: identity,
      raw: data,
    );
  }

  /// A field that is a string on most records and something else on a few.
  /// `portrait` is the known case: on an account whose picture was uploaded
  /// through the admin console it is a file object, `{ url, path, name … }`,
  /// not a URL. A hard cast there made sign-in throw for exactly the people
  /// most likely to be testing: the ones with a profile photo.
  static String? _str(dynamic v) {
    if (v == null) return null;
    if (v is String) return v.isEmpty ? null : v;
    if (v is Map) {
      for (final k in ['url', 'path', 'name']) {
        final inner = v[k];
        if (inner is String && inner.isNotEmpty) return inner;
      }
      return null;
    }
    return v.toString();
  }

  String get displayName =>
      (name != null && name!.isNotEmpty) ? name! : email;
}

/// What came back from an attempt to sign in.
///
/// Deliberately not a token. Sign-in has three possible endings and one of them
/// — a verification challenge — carries no session at all. Returning a token
/// forced every caller to notice that on their own, and two shipped apps did
/// not: they read a challenge as success, held an empty token, and threw the
/// person out on the first real request. As a sealed type the compiler asks the
/// question instead, and forgetting the case is a build error rather than a
/// sign-in loop in production.
///
/// ```dart
/// switch (await appmint.customers.signIn(email, password)) {
///   case SignedIn(:final user):
///     // there is a session; go
///   case NeedsVerification(:final challenge):
///     // ask for the code, then challenge.verify(code)
///   case SignInRejected(:final message):
///     // show message
/// }
/// ```
sealed class SignInResult {
  const SignInResult();
}

/// There is a session. Calls made from here carry the person's token.
final class SignedIn extends SignInResult {
  final AppmintUser user;
  const SignedIn(this.user);
}

/// The password was right, but the organization wants a second factor. No
/// session exists yet; [challenge] is how you finish.
final class NeedsVerification extends SignInResult {
  final VerificationChallenge challenge;
  const NeedsVerification(this.challenge);
}

/// The server refused — wrong password, unknown account, locked out.
/// [message] is the server's own wording and is safe to show.
final class SignInRejected extends SignInResult {
  final String message;
  final AppmintException? error;
  const SignInRejected(this.message, [this.error]);
}

/// A sign-in waiting for a verification code.
///
/// Holds the challenge token so callers never handle it. Live until it is
/// verified, cancelled, or it expires on the server (about ten minutes) — after
/// which [verify] reports that plainly and the person signs in again.
class VerificationChallenge {
  /// How the code reached them right now. Changes if [sendByAnotherMethod]
  /// is used.
  VerificationMethod method;

  /// The server's own sentence — "Verification code sent to your email",
  /// "Enter the code from your authenticator app".
  final String message;

  /// Where the code was sent, when it was sent anywhere.
  final String? sentTo;

  /// True when the challenge was raised because this device is unrecognised
  /// rather than because the account carries a second factor.
  final bool isNewDevice;

  final String token;

  final Future<SignInResult> Function(String code, {bool trustDevice}) _verify;
  final Future<bool> Function(VerificationMethod? method) _resend;
  final void Function() _cancel;

  VerificationChallenge({
    required this.method,
    required this.message,
    required this.token,
    required this.isNewDevice,
    required Future<SignInResult> Function(String code, {bool trustDevice}) verify,
    required Future<bool> Function(VerificationMethod? method) resend,
    required void Function() cancel,
    this.sentTo,
  })  : _verify = verify,
        _resend = resend,
        _cancel = cancel;

  /// Finish the sign-in with the code the person typed.
  ///
  /// A wrong code comes back as [SignInRejected] with the server's wording and
  /// the challenge stays alive, so they can try again. Set [trustDevice] to
  /// stop this device being challenged again for a while — the difference
  /// between asking once and asking at every launch.
  Future<SignInResult> verify(String code, {bool trustDevice = true}) =>
      _verify(code, trustDevice: trustDevice);

  /// Send the same code again by the same route.
  Future<bool> resend() => _resend(null);

  /// Send a code by a different route — the way out when the default factor is
  /// an authenticator app on a phone that is lost, dead or elsewhere. Any
  /// factor the account has enrolled can answer the challenge, so this changes
  /// only how the code arrives.
  Future<bool> sendByAnotherMethod(VerificationMethod method) => _resend(method);

  /// Abandon it and go back to the sign-in form.
  void cancel() => _cancel();
}
