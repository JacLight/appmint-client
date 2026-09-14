# appmint_flutter_client

Talk to an Appmint (appengine) backend from Flutter — app authentication, staff
and customer sign-in, and reads and writes over any datatype.

```yaml
dependencies:
  appmint_flutter_client:
    path: ../appmint-client/appmint_flutter_client
```

## Point it at your organization

```dart
final appmint = Appmint(const AppmintConfig(
  baseUrl: 'https://appengine.appmint.io',
  orgId: 'acme',
  appId: 'acme-mobile',
  appKey: '…',
  appSecret: '…',
));
```

That is the last time you think about app authentication. The client fetches the
app token on the first call, renews it when it expires, retries the fetch only
when the request never reached the server, and stamps `orgid` on everything.

> Those app credentials are **not a secret** in a shipped binary — anyone can
> read them out of an APK or IPA. They identify the app; they do not protect it.
> What protects a request is the signed-in person's token.

## Sign somebody in

Two kinds of people sign in, they are different records on the server, and the
client keeps them apart because the difference is real:

```dart
appmint.staff.signIn(email, password);      // employees, managers, admins
appmint.customers.signIn(email, password);  // the people you serve
```

Sign-in does not return a token. It returns one of three endings, and the
compiler makes you handle all of them:

```dart
switch (await appmint.customers.signIn(email, password)) {
  case SignedIn(:final user):
    // there is a session — go
  case NeedsVerification(:final challenge):
    // the password was right; a code is needed
  case SignInRejected(:final message):
    showError(message);  // the server's own wording
}
```

This shape exists because of a real outage. A verification challenge comes back
as an ordinary `200` with **no token in it**. Two shipped apps read that as
success, held an empty token, and threw people out on the first real request —
a sign-in loop with no mention of the code that had just been emailed. With a
sealed result, forgetting that case is a build error instead.

## Finish a verification

The challenge carries everything needed, including a way out when the second
factor is on a phone that is lost or dead:

```dart
case NeedsVerification(:final challenge):
  // challenge.method  → email | sms | authenticator
  // challenge.message → the server's sentence, safe to show
  // challenge.canResend via challenge.method.canResend

  final result = await challenge.verify(code);        // trustDevice: true by default
  await challenge.resend();                            // same route again
  await challenge.sendByAnotherMethod(VerificationMethod.email);
  challenge.cancel();                                  // back to the form
```

A wrong code comes back as `SignInRejected` and the challenge stays alive, so
they can try again. An authenticator code is computed on the device, so
`method.canResend` is false for it — do not offer "send it again" there.

## The other ways in

```dart
await appmint.customers.sendMagicCode(email);
await appmint.customers.verifyMagicCode(email, code);

await appmint.staff.signInWithPasscode(employeeId: '4471', pin: '123456');
await appmint.staff.signInWithPasscode(employeeId: '4471', cardUid: uid);
```

Passcode and card sign-in are for shared devices — a till, a host stand, a door
scanner — and the server deliberately exempts them from verification
challenges so a queue is never held up. That also makes them the way back in
when an organization has just switched two-factor on.

## Staying signed in

```dart
await appmint.auth.restore();              // once at startup
appmint.auth.changes.listen(...);          // sign-in, sign-out, forced sign-out
await appmint.auth.savedSessions();        // one-tap accounts, per organization
await appmint.auth.signInWithSaved(row);
await appmint.auth.signOut();
```

`signOut` clears the tokens and the cached person **and nothing else**. It does
not wipe your preference store: an app keeps its own settings there — paired
printers, card readers, the chosen location — and clearing those on sign-out has
in practice left a configured till unable to trade until somebody re-paired the
hardware.

## Reading and writing

Appengine has no fixed set of tables. Every record has a datatype, and the same
handful of calls work on all of them — including datatypes you define:

```dart
final page = await appmint.repository.find(
  'sf_order',
  filter: {'data.status': 'open'},
  pageSize: 20,
);

final created = await appmint.repository.create('my_datatype', {'title': 'Hello'});
await appmint.repository.updateFields('my_datatype', id, {'data.title': 'Renamed'});
await appmint.repository.delete('my_datatype', id);
```

`updateFields` takes **dot paths**, not a nested map — `{'data.settings.theme': 'dark'}`.
Passing a nested object replaces that whole branch, quietly.

`findByAttribute` matches **loosely**: a value can return records that merely
resemble it. Read what comes back and confirm each record before acting on it,
and never pipe its results into `delete` — that has destroyed live records.

Anything this package does not wrap is still one call away, with tokens and
headers handled:

```dart
await appmint.http.post('/storefront/pos/tab/$id/settle', body: {...});
```

## Testing

`MemorySessionStore` keeps everything in RAM, so tests need no platform
plugins:

```dart
Appmint(config, store: MemorySessionStore());
```

The suite in `test/` runs against a real backend:

```bash
flutter test --dart-define=APPMINT_BASE_URL=http://127.0.0.1:3399
```
