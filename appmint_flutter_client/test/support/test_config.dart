import 'package:appmint_flutter_client/appmint_flutter_client.dart';

/// Credentials for the live tests, supplied at run time — never committed.
///
///   flutter test \
///     --dart-define=APPMINT_BASE_URL=http://127.0.0.1:3399 \
///     --dart-define=APPMINT_ORG=demo \
///     --dart-define=APPMINT_APP_ID=... \
///     --dart-define=APPMINT_APP_KEY=... \
///     --dart-define=APPMINT_APP_SECRET=...
///
/// Or put them in `test/.env.test` (git-ignored) and source it first.
/// Without them the live tests skip rather than fail, so a fresh clone is green.
class TestConfig {
  static const baseUrl = String.fromEnvironment('APPMINT_BASE_URL');
  static const orgId = String.fromEnvironment('APPMINT_ORG');
  static const appId = String.fromEnvironment('APPMINT_APP_ID');
  static const appKey = String.fromEnvironment('APPMINT_APP_KEY');
  static const appSecret = String.fromEnvironment('APPMINT_APP_SECRET');

  static bool get available =>
      baseUrl.isNotEmpty &&
      orgId.isNotEmpty &&
      appId.isNotEmpty &&
      appKey.isNotEmpty &&
      appSecret.isNotEmpty;

  static const skipReason =
      'Set APPMINT_BASE_URL, APPMINT_ORG, APPMINT_APP_ID, APPMINT_APP_KEY and '
      'APPMINT_APP_SECRET with --dart-define to run the live tests.';

  static AppmintConfig get config => const AppmintConfig(
        baseUrl: baseUrl,
        orgId: orgId,
        appId: appId,
        appKey: appKey,
        appSecret: appSecret,
      );

  static Appmint client() => Appmint(config, store: MemorySessionStore());
}
