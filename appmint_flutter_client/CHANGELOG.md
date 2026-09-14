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
