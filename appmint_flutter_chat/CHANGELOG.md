## 0.1.0

Moved into appmint-client from the appmint_go monorepo (where it was
`appmint_chat`), renamed to match the other packages here.

- Do not add a local "has joined" line on `agent-assigned` — the gateway
  already sends one as a system message, so the thread showed it twice.
