# echo-hunt-relay

Cloudflare Worker that lets two players duel over the internet instead of the
same Wi-Fi. One Durable Object per lobby code, holding two WebSockets and
forwarding frames between them.

The relay understands nothing about the game. It never sees a target it could
leak — it only shuffles opaque frames between two sockets.

## Deploy

```bash
cd worker
npx wrangler login          # opens a browser
npx wrangler deploy
```

`deploy` prints a URL like `https://echo-hunt-relay.<your-subdomain>.workers.dev`.
Put it in [`../Sources/Net/RelayLink.swift`](../Sources/Net/RelayLink.swift),
as `wss://` rather than `https://`:

```swift
static let defaultURL = "wss://echo-hunt-relay.your-subdomain.workers.dev"
```

Then rebuild (`./build.sh`) and both players need that same build.

Until you do this, the online menu options report "Relay not configured" rather
than failing with a confusing network error.

## Run it locally

```bash
npx wrangler dev
ECHO_HUNT_RELAY=ws://localhost:8787 ./build/EchoHunt.app/Contents/MacOS/EchoHunt
```

The env var overrides the baked-in URL, which is how the relay was tested
without deploying anything.

## Cost

Free tier: 100k requests/day, and Durable Objects are included on the free plan
when SQLite-backed (see the `new_sqlite_classes` migration in `wrangler.toml`).
A whole match is a few dozen messages over one socket, so a free account covers
far more play than you will ever generate.

## Protocol

```
GET /health                     → liveness text
GET /lobby/{CODE}?role=host     → 101 upgrade, creates the lobby
GET /lobby/{CODE}?role=guest    → 101 upgrade, or 404 if nobody is hosting
```

The relay injects exactly two frames of its own, in the shape Swift's `Codable`
emits, so both transports tell the game the same story:

```json
{"peerJoined":{}}    both players are present
{"peerLeft":{}}      the other side vanished
```

Everything else is forwarded byte for byte.
