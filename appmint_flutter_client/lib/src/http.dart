import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'call.dart';
import 'config.dart';
import 'errors.dart';

/// The one place a request is built, sent and read back.
///
/// Two tokens ride on every authenticated call and they answer different
/// questions. `Authorization: Bearer …` carries the **app** token and answers
/// "may this application talk to appengine at all". `x-client-authorization`
/// carries the **person's** token and answers "who is doing this". That naming
/// surprises everyone — the header called Authorization is not the user's — so
/// this client owns both and no caller ever names either one.
///
/// The app token is fetched on first use and renewed on expiry without anyone
/// asking. Callers only ever decide whether a call is on behalf of a signed-in
/// person ([sendUserToken]) or not.
class AppmintHttp {
  AppmintHttp(this.config);

  AppmintConfig config;

  String? _appToken;
  String? _userToken;

  /// Concurrent callers share one in-flight token fetch rather than each
  /// storming `/profile/app/key` on a cold start.
  Future<String?>? _pendingAppToken;

  /// Renew the person's token when the server says it has expired. Set by the
  /// auth layer; without it an expired session simply ends.
  Future<String?> Function()? onUserTokenRefresh;

  /// Called when the session cannot be recovered and the person must sign in
  /// again. Fires once, before the failing call throws.
  VoidCallback? onSessionExpired;

  /// Called after every request completes, successfully or not.
  ///
  /// Exists so a screen can show what the client actually did — which is the
  /// difference between a demo you watch and a demo you learn from. Never
  /// carries token values.
  void Function(AppmintCall call)? onCall;

  bool get hasUserToken => _userToken != null && _userToken!.isNotEmpty;

  /// The signed-in person's token, for the one place it has to leave the
  /// client: a socket handshake. A WebSocket cannot carry per-request headers,
  /// so the chat gateway takes the token in `auth` at connect time. Nothing
  /// else should read this — every HTTP call attaches it for you.
  String? get userToken => hasUserToken ? _userToken : null;

  /// The person's token, once they have signed in. Setting it does not
  /// validate it — the next call will.
  void setUserToken(String? token) => _userToken = token;

  void clearUserToken() => _userToken = null;

  /// Drop the app token so the next call fetches a fresh one. Useful after
  /// changing organization.
  void clearAppToken() => _appToken = null;

  // ── app authentication ────────────────────────────────────────────────

  /// Fetch the app token, or join the fetch already in flight.
  Future<String?> appToken() =>
      _pendingAppToken ??=
          _fetchAppToken().whenComplete(() => _pendingAppToken = null);

  Future<String?> _fetchAppToken() async {
    for (var attempt = 1; attempt <= config.transientRetries; attempt++) {
      final started = DateTime.now();
      try {
        final res = await http
            .post(
              Uri.parse('${config.baseUrl}/profile/app/key'),
              headers: {
                'Content-Type': 'application/json',
                'orgid': config.orgId,
              },
              body: jsonEncode({
                'appId': config.appId,
                'secret': config.appSecret,
                'key': config.appKey,
              }),
            )
            .timeout(config.timeout);

        if (res.statusCode >= 200 && res.statusCode < 300) {
          final body = jsonDecode(res.body);
          final token = body is Map ? body['token'] : null;
          if (token is String && token.isNotEmpty) {
            _appToken = token;
            _log('app token obtained');
            // Reported like any other call — it is the first half of the two
            // token story, and hiding it is what makes the model confusing.
            _emit('POST', '/profile/app/key', res.statusCode, started, false);
            return _appToken;
          }
        }
        _emit('POST', '/profile/app/key', res.statusCode, started, false);

        // The server answered and said no. Wrong credentials or wrong org —
        // repeating the call repeats the answer, so stop and say so clearly.
        throw AppmintAppAuthException(
          'The app could not authenticate with appengine. Check appId, key, '
          'secret and orgId (${res.statusCode}).',
          statusCode: res.statusCode,
          body: res.body,
        );
      } on AppmintAppAuthException {
        rethrow;
      } catch (e) {
        if (_isTransient(e) && attempt < config.transientRetries) {
          final backoff = Duration(milliseconds: 400 * attempt);
          _log('app token attempt $attempt failed (${_short(e)}); '
              'retrying in ${backoff.inMilliseconds}ms');
          await Future<void>.delayed(backoff);
          continue;
        }
        throw AppmintNetworkException(
          'Could not reach appengine at ${config.baseUrl}: ${_short(e)}',
        );
      }
    }
    throw AppmintNetworkException(
      'Could not reach appengine at ${config.baseUrl}.',
    );
  }

  // ── requests ──────────────────────────────────────────────────────────

  Future<dynamic> get(
    String path, {
    Map<String, String>? query,
    bool sendUserToken = true,
  }) =>
      send('GET', path, query: query, sendUserToken: sendUserToken);

  Future<dynamic> post(
    String path, {
    Object? body,
    bool sendUserToken = true,
  }) =>
      send('POST', path, body: body, sendUserToken: sendUserToken);

  Future<dynamic> put(String path, {Object? body, bool sendUserToken = true}) =>
      send('PUT', path, body: body, sendUserToken: sendUserToken);

  Future<dynamic> patch(
    String path, {
    Object? body,
    bool sendUserToken = true,
  }) =>
      send('PATCH', path, body: body, sendUserToken: sendUserToken);

  Future<dynamic> delete(String path, {bool sendUserToken = true}) =>
      send('DELETE', path, sendUserToken: sendUserToken);

  Future<dynamic> send(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
    bool sendUserToken = true,
    bool retriedAfterRenew = false,
  }) async {
    if (_appToken == null) await appToken();

    final isGet = method.toUpperCase() == 'GET';
    final params = <String, String>{
      ...?query?.entries
          .where((e) {
            final v = e.value.trim();
            return v.isNotEmpty && v != 'null' && v != 'NaN';
          })
          .fold<Map<String, String>>({}, (m, e) => m..[e.key] = e.value),
      // A browser will happily serve a cached GET after a write, so a list can
      // come back without the row just created. Live data must not be cached.
      if (isGet && kIsWeb) '_ts': DateTime.now().microsecondsSinceEpoch.toString(),
    };

    final uri = Uri.parse('${config.baseUrl}$path')
        .replace(queryParameters: params.isEmpty ? null : params);
    final encoded = body == null ? null : jsonEncode(body);

    _log('$method $path');
    final started = DateTime.now();

    http.Response? res;
    for (var attempt = 1; attempt <= config.transientRetries; attempt++) {
      if (_appToken == null) await appToken();
      try {
        res = await _dispatch(method, uri, _headers(sendUserToken), encoded);
        break;
      } catch (e) {
        if (_isTransient(e) && attempt < config.transientRetries) {
          final backoff = Duration(milliseconds: 400 * attempt);
          _log('$method $path attempt $attempt failed (${_short(e)}); '
              'retrying in ${backoff.inMilliseconds}ms');
          await Future<void>.delayed(backoff);
          continue;
        }
        throw AppmintNetworkException(
            'Network error (${e.runtimeType}): ${_short(e)}');
      }
    }

    if (res!.statusCode == 401 && !retriedAfterRenew) {
      // A 401 is ambiguous: either the app token aged out or the person's did.
      // Renew the app token first — it is free and needs nobody — and only
      // then conclude the session is what expired.
      _appToken = null;
      await appToken();

      if (sendUserToken && hasUserToken && onUserTokenRefresh != null) {
        final renewed = await onUserTokenRefresh!().catchError((_) => null);
        if (renewed != null && renewed.isNotEmpty) _userToken = renewed;
      }

      return send(
        method,
        path,
        body: body,
        query: query,
        sendUserToken: sendUserToken,
        retriedAfterRenew: true,
      );
    }

    if (res.statusCode == 401 && sendUserToken && hasUserToken) {
      _emit(method, path, res.statusCode, started, sendUserToken);
      clearUserToken();
      onSessionExpired?.call();
      throw const AppmintSessionExpiredException();
    }

    _emit(method, path, res.statusCode, started, sendUserToken);
    return _read(res);
  }

  /// Multipart upload against a path that accepts a `file` field.
  Future<Map<String, dynamic>> upload(
    String path, {
    required List<int> bytes,
    required String fileName,
    Map<String, String>? fields,
    String field = 'file',
  }) async {
    if (_appToken == null) await appToken();

    final req = http.MultipartRequest('POST', Uri.parse('${config.baseUrl}$path'))
      ..headers.addAll(_headers(true)..remove('Content-Type'))
      ..files.add(http.MultipartFile.fromBytes(field, bytes, filename: fileName));
    if (fields != null) req.fields.addAll(fields);

    final res = await http.Response.fromStream(
      await req.send().timeout(config.timeout * 2),
    );
    final body = _read(res);
    return body is Map ? Map<String, dynamic>.from(body) : <String, dynamic>{};
  }

  // ── internals ─────────────────────────────────────────────────────────

  Map<String, String> _headers(bool sendUserToken) {
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'Cache-Control': 'no-cache, no-store',
      'Pragma': 'no-cache',
      'orgid': config.orgId,
      'shared-org-id': config.orgId,
      if (config.domainAsOrg) 'domainAsOrg': 'true',
      'Authorization': 'Bearer ${_appToken ?? ''}',
      if (sendUserToken && hasUserToken)
        'x-client-authorization': 'Bearer $_userToken',
    };
  }

  Future<http.Response> _dispatch(
    String method,
    Uri uri,
    Map<String, String> headers,
    String? body,
  ) {
    final t = config.timeout;
    switch (method.toUpperCase()) {
      case 'GET':
        return http.get(uri, headers: headers).timeout(t);
      case 'POST':
        return http.post(uri, headers: headers, body: body).timeout(t);
      case 'PUT':
        return http.put(uri, headers: headers, body: body).timeout(t);
      case 'PATCH':
        return http.patch(uri, headers: headers, body: body).timeout(t);
      case 'DELETE':
        return http.delete(uri, headers: headers).timeout(t);
      default:
        throw AppmintException('Unsupported HTTP method $method');
    }
  }

  dynamic _read(http.Response res) {
    if (res.statusCode >= 200 && res.statusCode < 300) {
      if (res.body.isEmpty) return null;
      try {
        return jsonDecode(res.body);
      } on FormatException {
        return res.body; // some routes answer with a bare string
      }
    }

    // appengine reports failures in two shapes: its own exception filter emits
    // { statusCode, error, reason, path }, while a raw NestJS HttpException
    // emits { statusCode, message, error }. The sentence a person should read
    // may be under either key, so try both before inventing wording.
    String? message;
    String? reason;
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map) {
        reason = decoded['reason'] as String?;
        for (final key in ['message', 'error', 'msg']) {
          final v = decoded[key];
          if (v is String && v.isNotEmpty) {
            message = v;
            break;
          }
          if (v is List && v.isNotEmpty) {
            message = v.join('; ');
            break;
          }
        }
      }
    } catch (_) {/* not JSON */}

    if (config.logRequests) {
      debugPrint('[appmint] ${res.statusCode} ${res.request?.url}');
      if (res.body.isNotEmpty) {
        debugPrint('[appmint]   ${_clip(res.body, 500)}');
      }
    }

    throw AppmintException(
      message ?? _fallbackMessage(res),
      statusCode: res.statusCode,
      reason: reason,
      body: res.body,
    );
  }

  String _fallbackMessage(http.Response res) {
    switch (res.statusCode) {
      case 401:
        return 'Please sign in again.';
      case 403:
        return 'You do not have permission to do that.';
      case 404:
        return 'Not found: ${res.request?.url.path ?? ''}';
      default:
        return res.statusCode >= 500
            ? 'The server had a problem. Please try again.'
            : 'Request failed (${res.statusCode}).';
    }
  }

  void _emit(
    String method,
    String path,
    int status,
    DateTime started,
    bool sentUserToken,
  ) {
    final observer = onCall;
    if (observer == null) return;
    observer(AppmintCall(
      method: method.toUpperCase(),
      path: path,
      status: status,
      took: DateTime.now().difference(started),
      appAuthenticated: _appToken != null,
      sentUserToken: sentUserToken && hasUserToken,
      at: started,
    ));
  }

  /// A failure that never reached the server, so retrying is worth trying. A
  /// real HTTP response — any status — is not transient.
  static bool _isTransient(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('socketexception') ||
        s.contains('connection refused') ||
        s.contains('connection reset') ||
        s.contains('connection closed') ||
        s.contains('failed host lookup') ||
        s.contains('network is unreachable') ||
        s.contains('timeoutexception') ||
        s.contains('timed out');
  }

  void _log(String line) {
    if (config.logRequests) debugPrint('[appmint] $line');
  }

  static String _short(Object e) => _clip(e.toString(), 120);

  static String _clip(String s, int n) =>
      s.length > n ? '${s.substring(0, n)}…' : s;
}
