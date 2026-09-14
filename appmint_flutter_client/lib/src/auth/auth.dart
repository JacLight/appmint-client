import 'dart:async';

import '../errors.dart';
import '../http.dart';
import 'results.dart';
import 'session_store.dart';

/// Signing people in, and keeping them signed in.
///
/// Reach it as `appmint.staff` or `appmint.customers` depending on who is
/// signing in; everything after that — tokens, refresh, remembered accounts —
/// is shared and handled here.
class AppmintAuth {
  AppmintAuth(this._http, this.store) {
    _http.onUserTokenRefresh = _refreshAccessToken;
    _http.onSessionExpired = () {
      _user = null;
      _refreshToken = null;
      _changes.add(null);
      unawaited(store.clearSession());
    };
  }

  final AppmintHttp _http;
  final SessionStore store;

  final _changes = StreamController<AppmintUser?>.broadcast();

  AppmintUser? _user;
  String? _refreshToken;

  /// Sign-in for employees, managers and administrators.
  late final IdentityAuth staff = IdentityAuth._(this, Identity.staff);

  /// Sign-in for the people the organization serves.
  late final IdentityAuth customers = IdentityAuth._(this, Identity.customer);

  /// Whoever is signed in, or null.
  AppmintUser? get currentUser => _user;

  bool get isSignedIn => _user != null && _http.hasUserToken;

  /// Emits on every sign-in, sign-out and forced sign-out. Wrap it in whatever
  /// state management the app already uses.
  Stream<AppmintUser?> get changes => _changes.stream;

  /// Bring back a session stored on this device, if there is a live one.
  ///
  /// Call once at startup. Returns null when nobody is signed in — including
  /// when the stored token has aged out, in which case the remembered account
  /// stays in [savedSessions] so signing back in is one tap and a password.
  Future<AppmintUser?> restore() async {
    final access = await store.readAccessToken();
    if (access == null || access.isEmpty) return null;

    _refreshToken = await store.readRefreshToken();
    _http.setUserToken(access);

    final stored = await store.readUser();
    if (stored == null) {
      await signOut();
      return null;
    }

    _user = AppmintUser.fromJson(
      stored,
      stored['__identity'] == 'staff' ? Identity.staff : Identity.customer,
    );
    _changes.add(_user);
    return _user;
  }

  /// End the session on this device.
  ///
  /// Clears the tokens and the cached person. Remembered accounts and anything
  /// the app itself stored are left alone.
  Future<void> signOut() async {
    _user = null;
    _refreshToken = null;
    _http.clearUserToken();
    await store.clearSession();
    _changes.add(null);
  }

  // ── remembered accounts ───────────────────────────────────────────────

  /// Accounts this device has signed into, newest first.
  Future<List<SavedSession>> savedSessions() => store.readSavedSessions();

  /// Remove one remembered account. Does not touch the current session.
  Future<void> forgetSession(String email, String orgId) async {
    final all = await store.readSavedSessions();
    all.removeWhere((s) => s.email == email && s.orgId == orgId);
    await store.writeSavedSessions(all);
  }

  /// Sign in again as a remembered account without a password.
  ///
  /// Returns [SignInRejected] when the stored token can no longer be renewed —
  /// the row is marked expired so the sign-in screen can say so and ask for a
  /// password instead of failing silently.
  Future<SignInResult> signInWithSaved(SavedSession session) async {
    if (session.expired || session.accessToken.isEmpty) {
      return const SignInRejected(
        'That session has expired — please sign in with your password.',
      );
    }

    _http.setUserToken(session.accessToken);
    _refreshToken = session.refreshToken;

    final renewed = await _refreshAccessToken();
    if (renewed == null || renewed.isEmpty) {
      final all = await store.readSavedSessions();
      final i = all.indexWhere(
          (s) => s.email == session.email && s.orgId == session.orgId);
      if (i >= 0) {
        all[i] = all[i].copyWith(expired: true);
        await store.writeSavedSessions(all);
      }
      _http.clearUserToken();
      return const SignInRejected(
        'That session has expired — please sign in with your password.',
      );
    }

    final stored = await store.readUser();
    if (stored != null) {
      _user = AppmintUser.fromJson(stored, session.identity);
      _changes.add(_user);
      return SignedIn(_user!);
    }
    return const SignInRejected('Please sign in with your password.');
  }

  // ── internals shared by both identities ───────────────────────────────

  Future<String?> _refreshAccessToken() async {
    final refresh = _refreshToken;
    if (refresh == null || refresh.isEmpty) return null;
    final identity = _user?.identity ?? Identity.customer;
    try {
      final res = await _http.post(
        identity == Identity.staff
            ? '/profile/user/refresh'
            : '/profile/customer/refresh',
        body: {'refreshToken': refresh},
        sendUserToken: false,
      );
      final map = res is Map ? Map<String, dynamic>.from(res) : null;
      final token = _token(map);
      if (token == null || token.isEmpty) return null;
      _refreshToken = _refreshOf(map) ?? refresh;
      await store.writeTokens(token, _refreshToken!);
      return token;
    } catch (_) {
      return null;
    }
  }

  static String? _token(Map<String, dynamic>? m) {
    if (m == null) return null;
    for (final k in ['token', 'accessToken', 'access_token']) {
      final v = m[k];
      if (v is String && v.isNotEmpty) return v;
    }
    return null;
  }

  static String? _refreshOf(Map<String, dynamic>? m) {
    if (m == null) return null;
    for (final k in ['refreshToken', 'refresh_token']) {
      final v = m[k];
      if (v is String && v.isNotEmpty) return v;
    }
    return null;
  }

  /// Turn a sign-in response into a result.
  ///
  /// Three endings, and the order matters. A challenge is checked first because
  /// it arrives as a perfectly ordinary 200 that simply has no token in it —
  /// read as success it produces a session holding nothing, which is exactly
  /// how two apps shipped a sign-in loop.
  Future<SignInResult> _resolve(dynamic response, Identity identity) async {
    final map = response is Map ? Map<String, dynamic>.from(response) : null;
    if (map == null) {
      return const SignInRejected('The server sent a response we could not read.');
    }

    if (map['requiresTwoFactor'] == true) {
      return NeedsVerification(_challenge(map, identity));
    }

    final token = _token(map);
    if (token == null || token.isEmpty) {
      return const SignInRejected(
        'Sign-in did not return a session. Please try again.',
      );
    }

    final record = (map['user'] ?? map['customer']) is Map
        ? Map<String, dynamic>.from((map['user'] ?? map['customer']) as Map)
        : <String, dynamic>{};

    _refreshToken = _refreshOf(map) ?? token;
    _http.setUserToken(token);

    _user = AppmintUser.fromJson(record, identity);

    // The session is real the moment the server issued the token. Everything
    // below is convenience — keeping it on the device, remembering the account
    // for next time — and none of it may delay or fail the sign-in.
    //
    // Deliberately not awaited. A platform keystore can be slow, and on some
    // platforms it can simply never answer; awaiting it left a verified
    // sign-in hanging with the session already live behind the dialog. The
    // worst case here is somebody retypes a password tomorrow.
    unawaited(_persist(token, _refreshToken!, record, identity));

    _changes.add(_user);
    return SignedIn(_user!);
  }

  VerificationChallenge _challenge(Map<String, dynamic> map, Identity identity) {
    final token = (map['challengeToken'] ?? '').toString();
    // The resend closure needs to update the challenge it lives on, so the
    // variable is declared before the object it will hold.
    late final VerificationChallenge challenge;

    challenge = VerificationChallenge(
      method: VerificationMethod.parse(map['twoFactorMethod'] as String?),
      message: (map['message'] ?? 'Enter your verification code').toString(),
      sentTo: map['email'] as String?,
      isNewDevice: map['isNewDevice'] == true,
      token: token,
      verify: (code, {bool trustDevice = true}) async {
        try {
          final res = await _http.post(
            '/profile/security/challenge/verify',
            body: {
              'challengeToken': token,
              'code': code,
              'trustDevice': trustDevice,
            },
            sendUserToken: false,
          );
          return _resolve(res, identity);
        } on AppmintException catch (e) {
          return SignInRejected(e.message, e);
        }
      },
      resend: (VerificationMethod? method) async {
        try {
          await _http.post(
            '/profile/security/challenge/send',
            body: {
              'challengeToken': token,
              if (method != null) 'method': method.wireName,
            },
            sendUserToken: false,
          );
          if (method != null) challenge.method = method;
          return true;
        } catch (_) {
          return false;
        }
      },
      cancel: () {
        _http.clearUserToken();
      },
    );

    return challenge;
  }

  Future<void> _persist(
    String access,
    String refresh,
    Map<String, dynamic> record,
    Identity identity,
  ) async {
    try {
      await Future(() async {
        await store.writeTokens(access, refresh);
        await store.writeUser({...record, '__identity': identity.name});
        await _remember(access, refresh, _user!);
      }).timeout(const Duration(seconds: 5));
    } catch (e) {
      // Nothing to do but carry on: the person is signed in for this run, and
      // the next launch will simply ask again.
      assert(() {
        // ignore: avoid_print
        print('[appmint] could not store the session: $e');
        return true;
      }());
    }
  }

  Future<void> _remember(
    String access,
    String refresh,
    AppmintUser user,
  ) async {
    final all = await store.readSavedSessions();
    all.removeWhere(
        (s) => s.email == user.email && s.orgId == _http.config.orgId);
    all.insert(
      0,
      SavedSession(
        orgId: _http.config.orgId,
        email: user.email,
        identity: user.identity,
        name: user.name,
        avatar: user.avatar,
        accessToken: access,
        refreshToken: refresh,
        lastUsed: DateTime.now(),
      ),
    );
    await store.writeSavedSessions(all);
  }

  void dispose() => _changes.close();
}

/// Sign-in scoped to one kind of person.
class IdentityAuth {
  IdentityAuth._(this._auth, this.identity);

  final AppmintAuth _auth;
  final Identity identity;

  AppmintHttp get _http => _auth._http;

  /// Email and password.
  ///
  /// Always check the result — a verification challenge is a normal ending, not
  /// an error, and it carries no session.
  Future<SignInResult> signIn(String email, String password) async {
    try {
      final res = await _http.post(
        identity.signInPath,
        body: {'email': email.trim(), 'password': password},
        sendUserToken: false,
      );
      return _auth._resolve(res, identity);
    } on AppmintException catch (e) {
      return SignInRejected(e.message, e);
    }
  }

  /// Create an account and sign in.
  Future<SignInResult> signUp({
    required String email,
    required String password,
    String? firstName,
    String? lastName,
    String? phone,
  }) async {
    try {
      final res = await _http.post(
        identity.signUpPath,
        body: {
          'email': email.trim(),
          'password': password,
          if (firstName != null) 'firstName': firstName,
          if (lastName != null) 'lastName': lastName,
          if (phone != null) 'phone': phone,
        },
        sendUserToken: false,
      );
      return _auth._resolve(res, identity);
    } on AppmintException catch (e) {
      return SignInRejected(e.message, e);
    }
  }

  /// Email a six-digit code instead of asking for a password.
  ///
  /// This replaces the password rather than adding to it.
  Future<bool> sendMagicCode(String email) async {
    try {
      await _http.get(
        identity.magicCodePath,
        query: {'email': email.trim(), 'type': 'code'},
        sendUserToken: false,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Finish a magic-code sign-in.
  Future<SignInResult> verifyMagicCode(String email, String code) async {
    try {
      final res = await _http.post(
        identity.magicVerifyPath,
        body: {'email': email.trim(), 'code': code.trim()},
        sendUserToken: false,
      );
      return _auth._resolve(res, identity);
    } on AppmintException catch (e) {
      return SignInRejected(e.message, e);
    }
  }

  /// Employee id with a passcode, or a tap of a registered NFC card.
  ///
  /// For shared devices — a till, a host stand, a door scanner — where typing a
  /// password in front of a queue is the slowest thing in the building. Staff
  /// only; the server enforces whether a PIN is required alongside the card.
  ///
  /// This path is deliberately exempt from verification challenges so a busy
  /// terminal is never interrupted, which also makes it the way back in when
  /// an organization has turned on two-factor.
  Future<SignInResult> signInWithPasscode({
    required String employeeId,
    String? pin,
    String? cardUid,
  }) async {
    if (identity != Identity.staff) {
      throw const AppmintException(
        'Passcode sign-in is for staff. Use customers.signIn instead.',
      );
    }
    try {
      final res = await _http.post(
        '/profile/user/signin/passcode',
        body: {
          'employeeId': employeeId,
          if (pin != null && pin.isNotEmpty) 'pin': pin,
          if (cardUid != null && cardUid.isNotEmpty) 'cardUid': cardUid,
        },
        sendUserToken: false,
      );
      return _auth._resolve(res, identity);
    } on AppmintException catch (e) {
      return SignInRejected(e.message, e);
    }
  }
}
