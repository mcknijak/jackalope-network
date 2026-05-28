# Architecture Decisions

Running log of architecture decisions and the reasoning behind them. Newest entries at the top.

## 2026-05-28: Domain, Matrix federation, photo sharing

### Domain

Use `jackalope.network`, already owned via Porkbun.

DNS stays at Porkbun. Caddy will use Porkbun's API for DNS-01 challenges to issue wildcard certs for `*.jackalope.network`. No need to move DNS to Cloudflare unless and until a Cloudflare Tunnel is set up for public exposure.

### Matrix federation: start closed, preserve reversibility

**Decision:** run Synapse non-federated. Set `server_name: jackalope.network` so user IDs are clean (`@you:jackalope.network`) and the option to federate later stays open.

**Why closed:**

- Federation requires Synapse to be reachable from the public internet, which conflicts with the rest of the stack being Tailscale-only.
- Synapse plus federation eats CPU, RAM, and Postgres disk space (large public rooms can balloon the DB by tens of GB).
- More attack surface. Synapse federation code is the area most worth patching promptly.
- Federated DM spam is a known annoyance.
- The friend group is small, trusted, and not already on Matrix elsewhere, so the upside is low.

**Reversibility:**

- Closed back to federated, at the server level: edit `homeserver.yaml`, expose the federation port, restart. Easy.
- One important footnote at the room level: every Matrix room has an immutable `m.federate` flag set at creation time. Rooms created while federation is disabled default to `m.federate: false` and can never federate, even after the server is opened up. New rooms created after federation is enabled work fine, but old room histories stay local-only.
- **Mitigation, done at every room creation while closed:** explicitly set `m.federate: true` (Element's "Allow users on other servers to join" toggle, on by default). This keeps every room future-federation-ready even though the server itself is closed.

### Photo sharing

Immich's built-in "share album via link" is sufficient. No separate gallery app needed.

**Implication for networking:** link recipients have to load the Immich web UI to view a shared album, so the Immich domain must be publicly reachable. Everything else stays Tailscale-only. The cleanest fit is a Cloudflare Tunnel that exposes only `photos.jackalope.network`. This is the one app with a public surface.

Trade-off: this puts DNS for at least the `photos` subdomain on Cloudflare (or routes that one host via Cloudflare Tunnel while the rest stays on Porkbun DNS). Either approach is fine. Defer the exact wiring until app setup.
