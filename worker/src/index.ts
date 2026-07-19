/**
 * Echo Hunt relay.
 *
 * One Durable Object per lobby code, holding at most two WebSockets and
 * forwarding messages between them verbatim. The relay understands nothing
 * about the game — it never sees a target it could leak, because it only
 * shuffles opaque frames between two players.
 *
 * Traffic is tiny by design: a handful of messages per round, since the game
 * computes its haptics locally and never streams anything.
 */

export interface Env {
  LOBBY: DurableObjectNamespace;
}

/** Frames the relay itself injects, in the same shape Swift's Codable emits. */
const PEER_JOINED = JSON.stringify({ peerJoined: {} });
const PEER_LEFT = JSON.stringify({ peerLeft: {} });

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (url.pathname === "/" || url.pathname === "/health") {
      return new Response("echo-hunt relay ok\n", {
        headers: { "content-type": "text/plain" },
      });
    }

    const match = url.pathname.match(/^\/lobby\/([A-Za-z0-9]{1,16})$/);
    if (!match) return new Response("not found", { status: 404 });

    const code = match[1].toUpperCase();
    // Same code -> same object, anywhere in the world. This is what makes a
    // five-character code enough to find each other with no discovery.
    const id = env.LOBBY.idFromName(code);
    return env.LOBBY.get(id).fetch(request);
  },
};

export class Lobby {
  private host: WebSocket | null = null;
  private guest: WebSocket | null = null;

  constructor(
    private state: DurableObjectState,
    private env: Env,
  ) {}

  async fetch(request: Request): Promise<Response> {
    if (request.headers.get("Upgrade") !== "websocket") {
      return new Response("expected websocket", { status: 426 });
    }

    const url = new URL(request.url);
    const role = url.searchParams.get("role");
    if (role !== "host" && role !== "guest") {
      return new Response("role must be host or guest", { status: 400 });
    }

    // A guest arriving before the host has nothing to join — say so plainly
    // rather than leaving them hanging on a silent socket.
    if (role === "guest" && !this.host) {
      return new Response("no such lobby", { status: 404 });
    }
    if (role === "host" && this.host) {
      return new Response("lobby code already in use", { status: 409 });
    }
    if (role === "guest" && this.guest) {
      return new Response("lobby is full", { status: 409 });
    }

    const pair = new WebSocketPair();
    const client = pair[0];
    const server = pair[1];
    server.accept();

    if (role === "host") {
      this.host = server;
    } else {
      this.guest = server;
    }

    server.addEventListener("message", (event: MessageEvent) => {
      const other = server === this.host ? this.guest : this.host;
      // Forward untouched; the relay is not a participant.
      if (other && other.readyState === WebSocket.READY_STATE_OPEN) {
        other.send(event.data);
      }
    });

    const close = () => {
      const wasHost = server === this.host;
      if (wasHost) this.host = null;
      else this.guest = null;

      const other = wasHost ? this.guest : this.host;
      if (other && other.readyState === WebSocket.READY_STATE_OPEN) {
        other.send(PEER_LEFT);
      }
    };
    server.addEventListener("close", close);
    server.addEventListener("error", close);

    // Both sides learn the match can begin at the same moment.
    if (this.host && this.guest) {
      for (const socket of [this.host, this.guest]) {
        if (socket.readyState === WebSocket.READY_STATE_OPEN) {
          socket.send(PEER_JOINED);
        }
      }
    }

    return new Response(null, { status: 101, webSocket: client });
  }
}
