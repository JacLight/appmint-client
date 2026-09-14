import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'results.dart';

/// An account this device has signed into before, offered as one-tap sign-in.
///
/// Kept per organization, so somebody who works across two orgs gets a row for
/// each rather than one overwriting the other.
class SavedSession {
  final String orgId;
  final String email;
  final Identity identity;
  final String? name;
  final String? avatar;
  final String accessToken;
  final String refreshToken;
  final DateTime lastUsed;

  /// Set once a stored token has been refused. The row stays — the person is
  /// still known, they just have to type a password again.
  final bool expired;

  const SavedSession({
    required this.orgId,
    required this.email,
    required this.identity,
    required this.accessToken,
    required this.refreshToken,
    required this.lastUsed,
    this.name,
    this.avatar,
    this.expired = false,
  });

  SavedSession copyWith({bool? expired, DateTime? lastUsed}) => SavedSession(
        orgId: orgId,
        email: email,
        identity: identity,
        accessToken: expired == true ? '' : accessToken,
        refreshToken: expired == true ? '' : refreshToken,
        lastUsed: lastUsed ?? this.lastUsed,
        name: name,
        avatar: avatar,
        expired: expired ?? this.expired,
      );

  Map<String, dynamic> toJson() => {
        'orgId': orgId,
        'email': email,
        'identity': identity.name,
        'name': name,
        'avatar': avatar,
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'lastUsed': lastUsed.toIso8601String(),
        'expired': expired,
      };

  factory SavedSession.fromJson(Map<String, dynamic> j) => SavedSession(
        orgId: (j['orgId'] ?? '').toString(),
        email: (j['email'] ?? '').toString(),
        identity: j['identity'] == 'staff' ? Identity.staff : Identity.customer,
        name: j['name'] as String?,
        avatar: j['avatar'] as String?,
        accessToken: (j['accessToken'] ?? '').toString(),
        refreshToken: (j['refreshToken'] ?? '').toString(),
        lastUsed:
            DateTime.tryParse((j['lastUsed'] ?? '').toString()) ?? DateTime(2000),
        expired: j['expired'] == true,
      );
}

/// Where tokens and remembered accounts live on the device.
///
/// Implement this to put them somewhere else — an in-memory one for tests, or
/// your own vault. [SecureSessionStore] is the default and is what you want
/// unless you have a reason.
abstract class SessionStore {
  Future<String?> readAccessToken();
  Future<String?> readRefreshToken();
  Future<void> writeTokens(String access, String refresh);
  Future<void> clearTokens();

  Future<Map<String, dynamic>?> readUser();
  Future<void> writeUser(Map<String, dynamic> user);

  Future<List<SavedSession>> readSavedSessions();
  Future<void> writeSavedSessions(List<SavedSession> sessions);

  /// Forget the signed-in person. Remembered accounts survive on purpose — a
  /// shared till should not have to be re-taught who works there.
  ///
  /// This clears only what this client wrote. It must never wipe the whole
  /// preference store: an app keeps its own settings there — paired printers,
  /// card readers, the chosen location, the home layout — and clearing them on
  /// sign-out has, in practice, left a configured till unable to trade until
  /// somebody paired the hardware again.
  Future<void> clearSession();
}

/// Tokens in the platform keystore, everything else in preferences.
class SecureSessionStore implements SessionStore {
  static const _kAccess = 'appmint.access_token';
  static const _kRefresh = 'appmint.refresh_token';
  static const _kUser = 'appmint.user';
  static const _kSaved = 'appmint.saved_sessions';

  final FlutterSecureStorage _secure;

  SecureSessionStore({FlutterSecureStorage? secure})
      : _secure = secure ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  @override
  Future<String?> readAccessToken() => _secure.read(key: _kAccess);

  @override
  Future<String?> readRefreshToken() => _secure.read(key: _kRefresh);

  @override
  Future<void> writeTokens(String access, String refresh) async {
    await _secure.write(key: _kAccess, value: access);
    await _secure.write(key: _kRefresh, value: refresh);
  }

  @override
  Future<void> clearTokens() async {
    await _secure.delete(key: _kAccess);
    await _secure.delete(key: _kRefresh);
  }

  @override
  Future<Map<String, dynamic>?> readUser() async {
    final raw = (await SharedPreferences.getInstance()).getString(_kUser);
    if (raw == null || raw.isEmpty) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> writeUser(Map<String, dynamic> user) async {
    await (await SharedPreferences.getInstance())
        .setString(_kUser, jsonEncode(user));
  }

  @override
  Future<List<SavedSession>> readSavedSessions() async {
    final raw = (await SharedPreferences.getInstance()).getString(_kSaved);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => SavedSession.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList()
        ..sort((a, b) => b.lastUsed.compareTo(a.lastUsed));
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> writeSavedSessions(List<SavedSession> sessions) async {
    await (await SharedPreferences.getInstance()).setString(
      _kSaved,
      jsonEncode(sessions.map((s) => s.toJson()).toList()),
    );
  }

  @override
  Future<void> clearSession() async {
    await clearTokens();
    await (await SharedPreferences.getInstance()).remove(_kUser);
  }
}

/// Keeps everything in memory. For tests, and for a kiosk that should forget
/// the moment it closes.
class MemorySessionStore implements SessionStore {
  String? _access;
  String? _refresh;
  Map<String, dynamic>? _user;
  List<SavedSession> _saved = [];

  @override
  Future<String?> readAccessToken() async => _access;
  @override
  Future<String?> readRefreshToken() async => _refresh;
  @override
  Future<void> writeTokens(String access, String refresh) async {
    _access = access;
    _refresh = refresh;
  }

  @override
  Future<void> clearTokens() async {
    _access = null;
    _refresh = null;
  }

  @override
  Future<Map<String, dynamic>?> readUser() async => _user;
  @override
  Future<void> writeUser(Map<String, dynamic> user) async => _user = user;
  @override
  Future<List<SavedSession>> readSavedSessions() async => _saved;
  @override
  Future<void> writeSavedSessions(List<SavedSession> s) async => _saved = s;
  @override
  Future<void> clearSession() async {
    await clearTokens();
    _user = null;
  }
}
