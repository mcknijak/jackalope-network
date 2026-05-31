# Architecture Decisions

Running log of architecture decisions and the reasoning behind them. Newest entries at the top.

## 2026-05-31: Temporary Netlify hosting for the welcome page

**Decision:** while the home server hardware is being assembled, host the welcome page at `jackalope.network` from Netlify (GitHub-linked, builds the `welcome/` directory on push). Config in `netlify.toml` at the repo root.

**Why this works as a placeholder:** the welcome page is static. The tailnet probe will fail (no server, no `probe.jackalope.network`), so every service tile renders dimmed with a "tailnet only" badge and the footer status reads "off tailnet: apps are private." For a placeholder this is the correct signal: the services exist conceptually, they are not yet reachable. When the server comes online and DNS is repointed, the tiles go live automatically with zero code change.

**Cutover plan once hardware is live:** in Porkbun, change the apex `jackalope.network` from the Netlify CNAME / ALIAS to a CNAME pointing at the Tailscale Funnel hostname (`<machine>.<tailnet>.ts.net`). Caddy then takes over serving the same `welcome/dist` content per the existing site block. The Netlify site can stay around as a passive fallback or be deleted; no operational reason to keep it.

**Why Netlify specifically:** GitHub-linked account already exists, free for this scale, single `netlify.toml` does the whole config, and the Vite output is exactly what Netlify expects. No vendor lock-in worth worrying about for a 63 KB static page.

## 2026-05-28: Unified jackalope.network SSO (Authelia/Authentik): considered, not adopted

A separate question from "Tailscale vs per-app login" came up: would a single login at the domain level (Authelia or Authentik doing forward-auth at Caddy) give a more polished "jackalope.network as one product" experience and replace the need for Tailscale?

**Decision:** no, kept Tailscale-only.

**Load-bearing reason:** native mobile apps (Element, Immich, Obsidian LiveSync, Jellyfin mobile) do not honor forward-auth. They hit `/api/*` directly. SSO at the proxy either blocks API traffic (mobile apps stop working entirely, which makes Immich and Jellyfin unusable) or allows API traffic through, in which case the app's own auth is what gates the mobile surface. The mobile surface is the primary access pattern for the most-used apps. So unified SSO would deliver the one-login UX for the web sessions but not actually eliminate the exposure that justified the tailnet-only posture in the first place. The mobile API surface would stay publicly reachable and would still be gated by app-level auth that has shipped pre-auth bugs in all four apps in the last two years.

**Full analysis with the three-architecture comparison and revisit triggers:** `docs/why-tailscale.md`, section "Considered and not adopted: unified jackalope.network SSO".

**Right next step if this ever comes up again:** hybrid (Tailscale-only by default, Authelia in front of Caddy for the specific app that needs unified public-plus-web access). Do not adopt the hybrid prematurely just because the pattern looks appealing.

## 2026-05-28: Access model (Tailscale-only vs public-with-app-auth)

Considered the alternative of dropping Tailscale and just exposing each app to the public internet behind its own login. Full analysis in `docs/why-tailscale.md`.

**Decision:** keep Tailscale-only as the default. Add public ingress (Tailscale Funnel preferred, Cloudflare Tunnel as the documented alternative) selectively for the one flow that genuinely needs it (photo share links).

**Load-bearing reason:** every one of the four apps in this stack (Immich, Jellyfin, CouchDB, Synapse) has shipped at least one auth-bypass or privilege-escalation CVE in roughly the last two years. The window between an upstream bug being public and the next monthly `docker compose pull` is the exposure window if any of these are directly on the internet. Tailscale collapses that risk surface by requiring a WireGuard key from an enrolled device before the app's auth code is ever reached.

**Cost accepted:** every person who needs access has to install Tailscale once. Small trusted group, this is fine. If friend-install friction ever becomes a real problem, the next step is Funnel for the specific app, not flipping the architecture.

**Future trigger to revisit:** if any service ever needs direct-browser, no-client public access for a regular user base, the next step is Authelia (or Authentik) for SSO in front of Caddy, not naked exposure.

## 2026-05-28: Security posture and welcome page

### Threat model

Locked in **threat model (b): targeted but not nation-state**. Full reasoning in `docs/security-audit.md`. Headlines: defend against someone who wants *this* data specifically and against physical drive theft; do not try to defend against state-level adversaries or against compromise of Tailscale/Porkbun/Cloudflare themselves.

### Encryption at rest

`/mnt/data` (the RAID1 mirror holding photos, notes, chat history, Matrix media) is LUKS2 with Argon2id. OS NVMe stays plaintext.

**Why this split:** LUKS on the boot disk would force an interactive unlock at every reboot. The OptiPlex has no IPMI, so that means physical access or Dropbear-in-initramfs (which adds an initramfs maintenance burden every kernel update). The OS disk does not hold any user-generated content; everything sensitive is on `/mnt/data`. The disk-stolen-from-OS scenario yields rotatable credentials (DB passwords, Porkbun/B2 API keys) but no actual user data. Documented in `docs/encryption-at-rest.md` along with the upgrade path to full-disk encryption if the threat model shifts.

**Operational tax:** every reboot needs an SSH session to run `cryptsetup open` and `mount`. Acceptable for a box that reboots rarely.

### Matrix E2EE on by default

`encryption_enabled_by_default_for_room_type: all`. Every new room is end-to-end encrypted unless the creator explicitly toggles it off. Bridges and bots that cannot handle E2EE stay supported via the opt-out toggle.

**Why opt-out instead of mandatory:** mandatory E2EE locks out bridges entirely. The user community is small enough that "the creator decides per room" is fine, and the default-on stance covers the realistic forgot-to-think-about-it case.

**Operational tax:** every user must set up Secure Backup on first login (Element Settings -> Security & Privacy -> Set up). Without it, losing device keys means losing message history. Documented in `matrix/README.md`.

### Welcome page

Static React + Vite app under `welcome/`. Caddy serves the built `dist/` at the root of `jackalope.network`. Design language mirrors the portfolio at jackmcknight.dev (Tokyo Night palette, FiraCode type, tile grid in the same shape as the portfolio's project cards).

**Why static rather than containerized:** the page is a few hundred lines of HTML once built. Running a Node container 24/7 to serve it is RAM spent and another image to update. Caddy is already running and is an excellent static file server.

**Off-tailnet UX:** the page is public so it can be linked from the portfolio. But the apps are tailnet-only. A client-side probe (`fetch` against `probe.jackalope.network/ok`, a tailnet-only Caddy endpoint) decides on each load whether to render tiles as live links or as dimmed "tailnet only" cards. Off-tailnet visitors see the page and the bio but cannot interact with the apps.

**Build/deploy:** `cd welcome && npm run build`, output to `welcome/dist/` (gitignored). Caddy bind-mounts that directory read-only. Updates require rerunning `npm run build`; Caddy serves new files on the next request.

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

**Implication for networking:** link recipients have to load the Immich web UI to view a shared album, so the Immich domain must be publicly reachable. Everything else stays Tailscale-only. `photos.jackalope.network` (and the root welcome page) are the only public surfaces.

**Update (2026-05-28, after access-model review):** went with **Tailscale Funnel** rather than Cloudflare Tunnel for the public ingress. Funnel uses the Tailscale daemon already running on the box, no second service to manage, and TCP passthrough lets Caddy keep terminating TLS with its own Let's Encrypt cert (DNS stays on Porkbun, no migration needed). Trade-offs vs Cloudflare are in `docs/why-tailscale.md`. The relevant give-up is no edge caching and no DDoS absorption; for low-volume photo-share use that is acceptable. Cloudflare Tunnel remains a viable fallback if Funnel limits ever bite.
