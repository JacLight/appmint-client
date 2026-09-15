## 0.1.2

- **Token refresh never worked.** The refresh routes read `refresh_token`;
  the client sent `refreshToken`, so every refresh was a 400 and every session
  ended after an hour with "sign in again". Found when the chat socket asked
  for a fresh token.
- `auth.refreshSession()` — refresh the access token now and return it, for a
  socket handshake that was refused as expired.
- `http.userToken` — the signed-in person's token, for the one place it has
  to leave the client: a socket handshake. `appmint_flutter_chat` reads it.

## 0.1.1

Found by building the events example against a live server.

- `repository.create` sends `isNew: true`. Without it AppEngine answers
  *"Not a new metrics, please use update or set the new property"*, which is
  not a sentence anybody should have to decode.
- `repository.create` throws when the server drops the write as an exact repeat
  of the previous one (it answers 200 with no body), instead of returning `{}`.
- Sign-in no longer throws for an account whose profile picture is a file
  object rather than a URL — which is every account that uploaded one through
  the admin console.
- Network errors name the underlying exception type.

## 0.1.0

First cut, extracted from the auth and HTTP layers of appmint_mobile, stowbo,
event_app and dfw_errand — four hand-copied implementations that had already
drifted apart.

- App authentication handled invisibly: fetched on first call, single-flight,
  renewed on expiry, retried only on failures that never reached the server.
- `staff` and `customers` sign-in kept as separate, visible paths.
- Sign-in returns a sealed `SignInResult`, so a verification challenge cannot be
  mistaken for a session.
- Verification challenges: verify, resend, switch method mid-challenge, cancel.
- Magic code, passcode and NFC card sign-in.
- Remembered accounts per organization, and a sign-out that clears only what
  this client wrote.
- Generic reads and writes over any datatype.
