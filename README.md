# appmint-client

Official clients for talking to an [Appmint](https://appmint.io) AppEngine
backend. One package per platform, one contract between them.

| Package | Platform | Status |
|---|---|---|
| [`appmint_flutter_client`](appmint_flutter_client) | Flutter / Dart | Working |
| [`appmint_flutter_chat`](appmint_flutter_chat) | Flutter / Dart — support chat screen over the `/chat` socket | Working |
| [`appmint_js_client`](appmint_js_client) | TypeScript — web, Node, React Native | In progress |

## What these are for

AppEngine is a REST API, and you can call it with `fetch` or `http` if you like.
These packages exist because three things about it are easy to get wrong, and
getting them wrong fails in confusing ways:

**Two tokens, not one.** `Authorization: Bearer …` carries the *app's* token and
answers "may this application talk to AppEngine at all". `x-client-authorization`
carries the *person's* token and answers "who is doing this". The header called
Authorization is not the user's — which surprises everybody. The clients own both
so you never name either.

**Two kinds of people.** Staff and customers are different records with
different sign-in routes, and they are not interchangeable. The clients keep that
distinction visible, because hiding a real difference turns it into a mystery.

**Signing in has three endings, not two.** A verification challenge comes back as
an ordinary `200` with no token in it. Read as success it produces a session
holding nothing — which is exactly how two shipped apps locked their users out of
a sign-in loop that never mentioned the code they had just been emailed. The
Flutter client returns a sealed result so the compiler asks the question.

## Quick look

```dart
final appmint = Appmint(const AppmintConfig(
  baseUrl: 'https://appengine.appmint.io',
  orgId: 'acme',
  appId: 'acme-mobile', appKey: '…', appSecret: '…',
));

switch (await appmint.customers.signIn(email, password)) {
  case SignedIn(:final user):              // there is a session
  case NeedsVerification(:final challenge): // ask for the code
  case SignInRejected(:final message):      // show it
}

final orders = await appmint.repository.find('sf_order', pageSize: 20);
```

## Installing

Neither package is published yet. Depend on this repository directly:

```yaml
# Flutter
dependencies:
  appmint_flutter_client:
    git:
      url: https://github.com/JacLight/appmint-client.git
      path: appmint_flutter_client
```

Each package's own README has the full guide.

## A note on app credentials

`appId`, `appKey` and `appSecret` identify your application. In a shipped mobile
binary they are **not secret** — anyone can read them out of an APK or an IPA.
Treat them as a name, not a password. What protects a request is the signed-in
person's token.

## Documentation

- [Build a Flutter app — tutorial](https://docs.appmint.io/docs/client-integration/flutter-tutorial)
- [Flutter client](https://docs.appmint.io/docs/client-integration/flutter-client)
- [Authentication](https://docs.appmint.io/docs/client-integration/flutter-authentication)
- [Making requests](https://docs.appmint.io/docs/client-integration/flutter-requests)
- [Example apps](https://github.com/JacLight/appmint-examples)

## Contributing

Both packages speak the same contract, so a change to one usually needs the same
change to the other. Please keep them in step — the reason this repository exists
is that four hand-copied clients drifted apart and half of them broke.

## Licence

MIT.
