# Networking: Tailscale, Caddy, and DNS

A from-scratch explanation of how the three networking pieces fit together, and what a request actually does when it hits one of the `*.jackalope.network` subdomains. Written for someone who has not internalized this model yet.

## The pieces

There are three things doing work, and they are easy to confuse:

1. **Tailscale** decides *who can reach the server at all*.
2. **DNS at Porkbun** decides *what name resolves to what IP address*.
3. **Caddy** decides *which app handles a request* once it arrives, and *encrypts the connection*.

A request from your laptop to `https://immich.jackalope.network` passes through all three, in that order.

## What a tailnet actually is

Tailscale builds a private network ("tailnet") on top of the public internet. Every device you log into your Tailscale account gets:

- A **stable IPv4 address** in the `100.64.0.0/10` CGNAT range (something like `100.78.42.5`). Yours, forever, until you forget the device.
- The ability to talk directly to every other device in the tailnet using that IP, regardless of what physical network either device is on (home WiFi, hotel WiFi, cell data, etc.).
- Encrypted point-to-point links (WireGuard under the hood). Tailscale's coordination server tells devices how to find each other but does not see the traffic.

For this homelab specifically, the server gets one tailnet address (call it `100.78.42.5`). Your laptop and phone are also on the tailnet. From any of those devices, `ping 100.78.42.5` works. From a device that is **not** on your tailnet, `ping 100.78.42.5` does not work and never will, because `100.x.x.x` is not routable on the public internet.

That is the core property the rest of the design relies on. The server is reachable at a stable address, but only from devices you have explicitly added.

### Where the Xfinity router fits in

It barely does. Tailscale punches through NATs without needing port forwards. You do not need to log into the Xfinity router and forward port 22 or 443 to your server. You do not need a static public IP. You do not need to know your public IP at all.

The only "inbound" traffic the Xfinity router will ever see for this homelab is the Tailscale Funnel path for the welcome page root and `photos.jackalope.network`, and even that does not need a port-forward (Funnel rides the same outbound WireGuard tunnel Tailscale already maintains; nothing arrives unsolicited at the gateway).

## What DNS is doing

DNS is the address book. When your browser sees `immich.jackalope.network`, it asks DNS "what IP is that?" and DNS answers with an address.

For this setup, you configure Porkbun's DNS panel so that every app subdomain points at the **server's tailnet IP**:

```
immich.jackalope.network    A    100.78.42.5
jellyfin.jackalope.network  A    100.78.42.5
couchdb.jackalope.network   A    100.78.42.5
matrix.jackalope.network    A    100.78.42.5
element.jackalope.network   A    100.78.42.5
```

(Replace `100.78.42.5` with whatever Tailscale assigned to your server.)

These DNS records are **public**. Anyone in the world can look them up and learn that `immich.jackalope.network` resolves to `100.78.42.5`. That is fine, because `100.78.42.5` is meaningless to them: they are not on your tailnet, so they cannot reach it.

This is the property that confuses people the first time. The names are public; the destinations are not. It is the IP-address equivalent of writing a friend's name on the outside of a sealed envelope: the name is visible, the contents are not.

### Why DNS at all, instead of just typing the IP?

Three reasons:

1. **TLS certs need names, not IPs.** Caddy issues `*.jackalope.network` certs from Let's Encrypt; you cannot get a public cert for `100.78.42.5`. The browser needs to see a hostname to validate the cert.
2. **Apps care which name was requested.** Caddy uses the Host header (the part after `https://`) to route to the right backend. Hitting `https://100.78.42.5` directly would not tell Caddy whether you wanted Immich or Jellyfin.
3. **Names survive IP changes.** If you ever rebuild the tailnet or replace the server, you change one DNS record per app instead of memorizing a new IP.

### MagicDNS as an alternative

Tailscale has a built-in feature called MagicDNS that gives every device a `<hostname>.<tailnet-name>.ts.net` name automatically. You could skip Porkbun DNS entirely and just visit `https://jackalope.tail-scale.ts.net:8096` for Jellyfin, etc.

We use Porkbun A records instead because:

- Caddy issues real public certs for `*.jackalope.network`, no browser warnings.
- One consistent naming scheme across all apps.
- The same name works whether you are on the tailnet or, in Immich's case, on the public internet via Tailscale Funnel.

MagicDNS still works as a fallback if Porkbun ever goes down (the box is reachable at `jackalope.<tailnet>.ts.net`).

## What Caddy is doing

Caddy is the single program that **all** inbound HTTPS requests touch. Every app sits behind it.

When you hit `https://immich.jackalope.network`, this is what happens:

1. **DNS lookup.** Your browser asks Porkbun "what is `immich.jackalope.network`?" Porkbun answers `100.78.42.5`.
2. **Tailscale routing.** Your laptop (which is on the tailnet) connects to `100.78.42.5` over the encrypted Tailscale link. The Xfinity router never sees this; it is point-to-point WireGuard.
3. **TLS handshake.** Caddy on the server, listening on port 443, presents the `*.jackalope.network` cert it issued itself via Let's Encrypt. Your browser validates the cert against the public Let's Encrypt root CA.
4. **Routing by Host header.** Caddy reads `Host: immich.jackalope.network` from the request and looks it up in `Caddyfile`. The matching site block says `reverse_proxy immich_server:2283`.
5. **Internal forward.** Caddy connects to `immich_server` on port 2283 over the internal Docker network named `proxy`. Immich never sees the TLS; it gets plain HTTP from Caddy.
6. **Response.** Immich responds, Caddy re-encrypts back to your browser over the same TLS connection.

The important parts of this chain for the security model:

- **Apps never publish ports to the host.** Look at any `compose.yml` file other than `caddy/compose.yml`: none of them have a `ports:` mapping. Apps listen only on the internal `proxy` Docker network. The only way to reach them is through Caddy, which means the only way to reach them is on a name Caddy knows about.
- **Caddy is the only thing on the tailnet-reachable ports.** Ports 80 and 443 on the server's tailnet IP are bound by Caddy alone.
- **TLS terminates at Caddy.** Apps speak plain HTTP to Caddy over the Docker bridge, which is fine because that traffic never leaves the host.

### Why DNS-01 instead of HTTP-01 for cert issuance

Let's Encrypt validates that you control a domain before issuing a cert. Two challenge types:

- **HTTP-01:** Let's Encrypt fetches a token from `http://<your-domain>/.well-known/acme-challenge/...`. Requires that the public internet can reach your server on port 80, which it cannot, because you have no port-forward.
- **DNS-01:** Let's Encrypt asks you to put a TXT record at `_acme-challenge.<your-domain>` and then it queries DNS. Requires that you can write to your DNS provider, which Caddy can via the Porkbun API.

We use DNS-01. The custom Caddy build (`caddy/Dockerfile`) includes the `caddy-dns/porkbun` plugin specifically for this. The two Porkbun API keys in `caddy/.env` are what authorize Caddy to add and remove the TXT records.

A nice side effect: you can also issue **wildcard certs** with DNS-01 (Let's Encrypt only allows wildcards via DNS-01). If you ever add a new subdomain, Caddy reuses an existing `*.jackalope.network` wildcard instead of issuing a fresh per-host cert. Faster, cleaner.

## The public exceptions: Tailscale Funnel for the welcome page and photo sharing

The welcome page root (`jackalope.network`) and `photos.jackalope.network` are the only hosts meant to be reachable from outside the tailnet. The welcome page is public because it links from the portfolio; photo sharing is public so friends can open share links without joining the tailnet. Everything else stays tailnet-only.

The mechanism is **Tailscale Funnel**. The Tailscale daemon you already installed on the server holds an outbound WireGuard connection to Tailscale's edge. Funnel reuses that connection in the reverse direction: requests from the public internet hit Tailscale's edge and are routed back through the existing tunnel to your server.

What happens on a request to `https://photos.jackalope.network`:

1. DNS for `photos.jackalope.network` is a CNAME to your machine's Tailscale hostname (`<machine>.<tailnet>.ts.net`).
2. The visitor's browser resolves the CNAME, gets the public IP of a Tailscale edge node, and connects there over HTTPS.
3. Tailscale's edge **does not terminate TLS**. Funnel is configured for TCP passthrough on 443, so the encrypted bytes flow straight through.
4. The bytes arrive on the server at the Tailscale daemon, which hands them to local port 443.
5. Caddy reads the SNI (`photos.jackalope.network`), presents the matching Let's Encrypt cert it issued itself, terminates TLS, and reverse-proxies to Immich on the internal Docker network.

What this buys you:

- **No port-forward on Xfinity.** Funnel rides the outbound WireGuard tunnel; nothing arrives at the gateway unsolicited.
- **Caddy keeps owning TLS.** No second cert authority in the picture, no Tailscale-managed `*.ts.net` cert appearing in the browser. The visitor sees a real `jackalope.network` cert.
- **One daemon, not two.** Tailscale is already running for the tailnet. Funnel is a feature of the same daemon, not a separate service like Cloudflare Tunnel would be.
- **The rest of the stack stays tailnet-only.** Only the welcome page root and `photos.jackalope.network` are publicly resolvable to a usable address. `immich.jackalope.network` (the tailnet-only name) and `photos.jackalope.network` (the public name) both route to the same Immich container, but through different paths.

What you give up vs Cloudflare Tunnel (which was the earlier plan, see `docs/why-tailscale.md` for the full comparison): no edge caching, no DDoS absorption, public traffic still consumes your home upload bandwidth. For low-volume photo sharing, acceptable. Cloudflare Tunnel remains a viable fallback if Funnel limits ever bite.

This is documented but deferred in the initial scaffold. Set it up when you actually want to share an album with someone, not before.

## The root domain: `jackalope.network`

The bare domain (no subdomain) is **publicly resolvable** and serves the welcome page. The reason: you plan to link to it from your portfolio, and a portfolio link that requires the visitor to be on your tailnet is a portfolio link that almost no one will follow.

The welcome page is just static HTML built from a Vite project. It does not contain any sensitive content. The tile links on it point to `immich.jackalope.network`, `jellyfin.jackalope.network`, etc., which are tailnet-only. A visitor not on your tailnet can see the page exists and read the bio, but clicking a tile from a public network just fails (the tile is dimmed and disabled if a client-side reachability probe fails, so the failure is graceful).

DNS plan:

```
jackalope.network           CNAME <machine>.<tailnet>.ts.net   (root, public via Funnel)
photos.jackalope.network    CNAME <machine>.<tailnet>.ts.net   (public via Funnel)
*.jackalope.network         A     100.78.42.5                   (every other subdomain, tailnet only)
```

Both public hosts ride the same Funnel endpoint. Caddy disambiguates by SNI and serves the correct cert + backend per Host header. No second `cloudflared`-style daemon needed; the Tailscale process is the only thing handling public ingress.

## Quick mental check

When you next find yourself debugging "why can't I reach X from Y," walk through the three layers in order:

1. Is the requesting device **on the tailnet** for any non-public hostname? (`tailscale status` on the device should list the server.)
2. Does **DNS** resolve the hostname to the right IP? (`dig immich.jackalope.network +short` should return the server's tailnet IP.)
3. Is **Caddy** healthy and does its log show the request arriving? (`docker compose logs -f caddy` on the server.)

If all three are fine and the app still does not respond, the bug is in the app, not the network.
