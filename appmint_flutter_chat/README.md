# appmint_flutter_chat

Customer-to-agent support chat for Flutter apps, over the AppEngine `/chat`
Socket.IO gateway. One screen you push; the agent answers from the Appmint
admin, Appmint Mobile, or anything else that speaks the gateway.

Speaks the same contract as the web chat widget, so nothing on the server
changes: connect with the customer's token in the handshake `auth`, thread id
`customer::{email}`, `chat-message` to send (no assistant ⇒ the human queue),
`chat-history` to load, `shareStatus` for typing, `updateMessageStatus` for read
receipts, and the `queued` / `agent-assigned` / `chat-ended` events coming back.

## Install

```yaml
dependencies:
  appmint_flutter_chat:
    git:
      url: https://github.com/JacLight/appmint-client.git
      path: appmint_flutter_chat
```

## Use it with the Flutter client

```dart
final config = AppmintChatConfig(
  endpoint: appmint.config.baseUrl,          // https://appengine.appmint.io
  orgId: appmint.config.orgId,
  user: AppmintChatUser(email: me.email, name: me.displayName),
  token: () async => appmint.http.userToken, // the CUSTOMER's token, never the app token
  supportName: 'Acme support',
);

Navigator.push(context, MaterialPageRoute(
  builder: (_) => AppmintSupportChatScreen(config: config),
));
```

`token` is called on every (re)connect, so a refreshed token is picked up.
Pass `onTokenExpired` to refresh when the gateway says the token is stale.

Want your own scaffold? `AppmintChatView(controller: AppmintChatController(config)..start())`
draws the thread and the composer; the controller exposes `connection`,
`agent`, `queue`, `peerTyping` and `messages` for a header of your own, and
`controller.service` exposes every socket event as a stream.

## What the agent sees

The first message lands in the support queue and every online agent gets a
`queue-notification`. Whoever picks it up joins the thread; their replies
arrive as `message`, and the customer's header changes to their name.
Reopening the screen later loads the same thread — `customer::{email}` never
changes.

Pass `configId` to route to one chat config's agents (and its AI, if it has
one) instead of everyone.

## Worked example

[`appmint_flutter_chat_demo`](https://github.com/JacLight/appmint-examples/tree/main/appmint_flutter_chat_demo)
in appmint-examples, with its tutorial at
[docs.appmint.io/docs/examples/flutter-chat](https://docs.appmint.io/docs/examples/flutter-chat).
