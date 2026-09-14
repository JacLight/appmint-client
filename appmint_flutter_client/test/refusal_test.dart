@Tags(['live'])
library;

import 'package:appmint_flutter_client/appmint_flutter_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_config.dart';

void main() {
  if (!TestConfig.available) {
    test('live tests skipped', () {}, skip: TestConfig.skipReason);
    return;
  }

  const email = String.fromEnvironment('APPMINT_TEST_EMAIL');

  test('a refusal keeps the server wording and is not called a network error',
      () async {
    final appmint = TestConfig.client();

    try {
      await appmint.http.post(
        '/profile/customer/signin',
        body: {
          'email': email.isEmpty ? 'nobody@example.com' : email,
          'password': 'wrong-on-purpose',
        },
        sendUserToken: false,
      );
      fail('a wrong password should not succeed');
    } catch (e) {
      expect(e, isA<AppmintException>());
      // A 400 is an answer. Dressing it up as a network failure sends people
      // to check their wifi instead of their password.
      expect(e, isNot(isA<AppmintNetworkException>()));
    }

    final result = await appmint.customers.signIn(
      email.isEmpty ? 'nobody@example.com' : email,
      'wrong-on-purpose',
    );
    expect(result, isA<SignInRejected>());
    expect(
      (result as SignInRejected).message.toLowerCase(),
      isNot(contains('network error')),
    );

    appmint.dispose();
  });
}
