@Tags(['live'])
library;

import 'package:appmint_flutter_client/appmint_flutter_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_config.dart';

/// Runs against a real appengine, with credentials passed in at run time —
/// see test/support/test_config.dart. Nothing here is committed.
///
/// Uses the in-memory session store so no platform plugins are needed.
void main() {
  if (!TestConfig.available) {
    test('live tests skipped', () {}, skip: TestConfig.skipReason);
    return;
  }

  Appmint build() => TestConfig.client();

  test('the app authenticates itself without anyone asking', () async {
    final appmint = build();
    final token = await appmint.http.appToken();
    expect(token, isNotNull);
    expect(token!.isNotEmpty, isTrue);
    appmint.dispose();
  });

  test('wrong credentials come back as a refusal, not an exception', () async {
    final appmint = build();
    final result = await appmint.customers.signIn(
      'nobody.here@example.com',
      'definitely-wrong',
    );
    expect(result, isA<SignInRejected>());
    expect((result as SignInRejected).message, isNotEmpty);
    appmint.dispose();
  });

  test('a verification challenge is a result, never a half-made session',
      () async {
    final appmint = build();
    final email = 'client.test.${DateTime.now().millisecondsSinceEpoch}'
        '@example.com';

    final created = await appmint.customers.signUp(
      email: email,
      password: 'Aaaaaaaa1!',
      firstName: 'Client',
      lastName: 'Test',
    );

    // The demo org requires a second factor, so even a brand-new account is
    // challenged. Whichever ending it is, there must never be a session
    // without a token behind it.
    switch (created) {
      case SignedIn(:final user):
        expect(appmint.http.hasUserToken, isTrue);
        expect(user.email, email);
      case NeedsVerification(:final challenge):
        expect(challenge.token, isNotEmpty);
        expect(appmint.auth.isSignedIn, isFalse,
            reason: 'a challenge must not leave the client looking signed in');

        final wrong = await challenge.verify('123456', trustDevice: false);
        expect(wrong, isA<SignInRejected>());
        expect(appmint.auth.isSignedIn, isFalse);
      case SignInRejected(:final message):
        fail('sign-up was refused: $message');
    }

    appmint.dispose();
  });

  test('reads go through with app auth alone', () async {
    final appmint = build();
    final page = await appmint.repository.find('setting', pageSize: 1);
    expect(page.items, isA<List<Map<String, dynamic>>>());
    appmint.dispose();
  });
}
