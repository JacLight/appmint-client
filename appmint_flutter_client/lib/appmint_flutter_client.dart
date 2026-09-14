/// Talk to an Appmint (appengine) backend from Flutter.
///
/// ```dart
/// final appmint = Appmint(const AppmintConfig(
///   baseUrl: 'https://appengine.appmint.io',
///   orgId: 'acme',
///   appId: '…', appKey: '…', appSecret: '…',
/// ));
///
/// switch (await appmint.customers.signIn(email, password)) {
///   case SignedIn(:final user):            // there is a session
///   case NeedsVerification(:final challenge):  // ask for the code
///   case SignInRejected(:final message):   // show it
/// }
///
/// final orders = await appmint.repository.find('sf_order', pageSize: 20);
/// ```
library;

export 'src/call.dart';
export 'src/config.dart';
export 'src/errors.dart';
export 'src/http.dart';
export 'src/repository.dart';
export 'src/auth/auth.dart';
export 'src/auth/results.dart';
export 'src/auth/session_store.dart';

import 'src/auth/auth.dart';
import 'src/config.dart';
import 'src/auth/session_store.dart';
import 'src/http.dart';
import 'src/repository.dart';

/// One organization's backend, ready to use.
///
/// Construct it once and keep it — it caches the app token and holds the
/// signed-in session. Nothing here asks you to think about which token goes in
/// which header, or to remember `orgid`: the client stamps all of that itself.
class Appmint {
  Appmint(AppmintConfig config, {SessionStore? store})
      : http = AppmintHttp(config),
        _store = store ?? SecureSessionStore() {
    auth = AppmintAuth(http, _store);
    repository = AppmintRepository(http);
  }

  /// The raw client, for endpoints this package does not wrap. Headers and
  /// tokens are still handled for you.
  final AppmintHttp http;

  final SessionStore _store;

  /// Sign-in, sessions and remembered accounts.
  late final AppmintAuth auth;

  /// Reads and writes over any datatype.
  late final AppmintRepository repository;

  /// Sign-in for employees, managers and administrators.
  IdentityAuth get staff => auth.staff;

  /// Sign-in for the people the organization serves.
  IdentityAuth get customers => auth.customers;

  AppmintConfig get config => http.config;

  /// Point the client at another organization.
  ///
  /// Ends the current session — a token issued for one organization is not
  /// valid for another — and drops the cached app token so the next call
  /// authenticates against the new one.
  Future<void> switchOrganization(String orgId) async {
    await auth.signOut();
    http.config = http.config.copyWith(orgId: orgId);
    http.clearAppToken();
  }

  void dispose() => auth.dispose();
}
