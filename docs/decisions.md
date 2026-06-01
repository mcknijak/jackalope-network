# Architecture Decisions

Running log of architecture decisions and the reasoning behind them. Newest entries at the top.

## 2026-06-01: OS pin: Debian 13 (Trixie), not Debian 12 (Bookworm)

**Decision:** new installs of the homelab box use Debian 13 (Trixie, currently at point release 13.5). Bookworm is fine for existing installs but not the right starting point for a fresh build in mid-2026.

**Why:** Bookworm's full security support ends June 10, 2026 and transitions to LTS-only (community-maintained, narrower package coverage). Bootstrapping on Bookworm today means planning a `dist-upgrade` to Trixie within weeks of standing the box up. Trixie has been out since August 2025, is on its fifth point release, and runs full Debian security support through August 2028 plus LTS through June 2030. Docker CE installs and runs identically on both (cgroups v2, systemd cgroup driver), so the compatibility argument for staying on Bookworm doesn't exist. The one Trixie gotcha being discussed in the community (systemd 256+ behavior inside unprivileged Proxmox LXCs) does not apply to bare-metal installs.

**How to apply:** README, initial-plan, and the bootstrap script header all reference Trixie. The bootstrap script itself resolves the apt codename from `/etc/os-release` at runtime, so it remains correct on either release without edits.

## 2026-06-01: Added four services (ebooks, spokenword, cabinet, portainer)

**Decision:** added four new services to the stack:

- **`ebooks/`**: Calibre-Web at `shelf.jackalope.network`. Stage 1.
- **`spokenword/`**: Audiobookshelf at `spokenword.jackalope.network`, with podcast support enabled. Stage 1.
- **`cabinet/`**: Paperless-ngx at `cabinet.jackalope.network`, with email ingestion from `receipts@jackalope.network`. Stage 2.
- **`portainer/`**: Portainer CE plus local agent at `portainer.jackalope.network`. Stage 1.

All four are tailnet-only. None get Funnel exposure.

### Ebooks: Calibre-Web over Kavita and Komga

**Decision:** Calibre-Web.

**Why:** the library is EPUB and PDF only, no comics or manga. Kavita's main differentiator (great comics / manga handling, OPDS-based progress sync to Kobo via KOReader) is wasted for a pure-prose library. Komga is comics-first and would feel awkward. Calibre-Web's reader, OPDS endpoint, and optional send-to-Kindle path are the right toolset for what's actually being read. The `DOCKER_MODS=linuxserver/mods:universal-calibre` add-on covers EPUB <-> MOBI conversion without needing the full Calibre desktop container.

### Audiobookshelf is the only serious self-hosted option

**Decision:** Audiobookshelf, with podcast library enabled in addition to audiobooks.

**Why:** there is no realistic competitor in the self-hosted audiobook space. Booksonic and Subsonic-derived servers are music-first with poor audiobook UX. Audiobookshelf has the first-party iOS app, multi-user listening progress, and a maintained podcast catcher. Combining audiobooks and podcasts in one app avoids running a second service (Snapcast, AntennaPod-server, etc.) for what is conceptually the same access pattern.

### Paperless-ngx for the document archive, with iPhone scan via Paperless Mobile

**Decision:** Paperless-ngx in `cabinet/`. iPhone scanning via the third-party **Paperless Mobile** iOS app rather than a Samba / WebDAV folder + Genius Scan flow.

**Why Paperless Mobile:** it uses Apple's VisionKit scanner under the hood, which is the same engine that Notes and Genius Scan use, so per-page scan quality is essentially identical to dedicated apps. The single-app workflow avoids running a Samba container (a non-trivial extra trust surface) and lets the uploader pick tag and correspondent at scan time, which a watched folder cannot.

### Inbound mail: dedicated Porkbun-hosted mailbox, not Cloudflare Email Routing, not self-hosted SMTP

**Decision:** purchase Porkbun Email Hosting ($24/year) for `jackalope.network` and create `receipts@jackalope.network` as a real IMAP mailbox. Paperless polls it directly. No Cloudflare Email Routing, no Mailgun, no self-hosted Postfix / Dovecot / Stalwart.

**Why not self-hosted SMTP:** Tailscale Funnel is HTTPS-only and does not pass port 25. Most residential ISPs block inbound 25, and the deliverability tax of running a self-hosted MX from a residential IP (no reverse DNS control, IP-warming requirements, ongoing Gmail / Outlook reputation work) is wildly disproportionate to the value of one receive-only mailbox. Setup cost: 2-3 days plus ongoing operational burden, for no functional gain.

**Why not Cloudflare Email Routing:** would require either moving DNS to Cloudflare (out of Porkbun) or maintaining a split DNS arrangement. The user is already a Porkbun customer with the rest of the DNS there. Cloudflare Email Routing forwards-only also means we'd still need a paid mailbox at Migadu / Fastmail / similar as the actual IMAP target. Two vendors for what one vendor (Porkbun) can do in a single product.

**Why not Resend (initial user suggestion):** Resend is a transactional sending API. It does not host inbound mailboxes. Flagged the conflation and pivoted.

**Result:** one vendor (Porkbun), one billing line, the mailbox `receipts@jackalope.network` is a real IMAP endpoint at `mail.porkbun.com`, paperless polls it, whitelist + auto-delete logic lives in paperless's mail rules. Setup is documented in `cabinet/README.md` under "Email ingestion."

### Ebooks and audiobooks treated as Obsidian-class for backups

**Decision:** include the full ebook library and the full spokenword library (audiobook files plus podcasts plus metadata) in restic snapshots at stage 2+, not just the application databases.

**Why:** technically these are re-acquirable (re-download from Libro.fm, re-purchase, re-rip CDs), which would put them in the Jellyfin "skip backups" bucket. But the actual storage size is small relative to photos and video (tens of GB vs. hundreds), the B2 cost difference is rounding error, and the convenience of a one-shot restore vs. "restore metadata, then re-acquire everything" is high. Treating them as Obsidian-class (file-level backup, not just DB) for a small dollar cost is the right trade.

### Portainer with the agent architecture from day one

**Decision:** deploy Portainer CE plus its local agent (not Portainer talking directly to the Docker socket), even though there is only one host today.

**Why:** the marginal complexity of the agent architecture is small, and it makes adding a second host (a Pi for off-site backups, a second SFF) a non-event: the second host runs only the agent and gets pointed at the existing Portainer. Tailnet-only access; never Funnel-exposed. The agent has Docker socket access, which is effectively root on the box, so the trust boundary is explicit in `portainer/README.md` and `docs/security-audit.md`.

## 2026-05-31: Staged hardware rollout instead of one big buy

**Decision:** introduce a three-stage lifecycle for the hardware build instead of jumping straight to the full RAID1-plus-backup design. Stage 1 is a used SFF office PC with internal disk only. Stage 2 adds one extra drive plus Backblaze B2. Stage 3 is the full mirror plus 3-2-1 backup design the existing docs describe. Full writeup in `docs/staged-rollout.md`.

**Why:** the up-front commitment of the stage-3 design (used PC plus two NAS drives plus an external USB plus a B2 account) is several hundred dollars and a meaningful weekend of bootstrap work. That's too much to spend before the question "do I actually want to live with this product" is answered. Phasing lets the trial be cheap (under $250 one-time) and lets the spend track actual usage.

**Load-bearing assumption for stage 1:** every data class on the box is a mirror of an upstream that still exists. Immich mirrors iCloud or Google Photos with the upstream service kept on. Obsidian LiveSync mirrors a vault still on the laptop and still backed up there. Matrix starts fresh and is being trialed, not relied on for history. Jellyfin media is re-rippable. If the stage-1 disk dies, the loss is annoyance, not data. This framing is what makes "no encryption, no backup" acceptable at stage 1 only.

**Friends and family commitment:** invite-others happens at stage 3 only. The moment someone else's data is on the box, the redundancy and backup story of stage 3 is the minimum responsible posture. Stages 1 and 2 are solo.

**B2 at stage 2:** turn on Backblaze B2 backup at stage 2 (not stage 3). Cost is $1 to $3 per month for tens of GB and the off-site copy is the cheapest insurance available. Stage 2 is 2-2-1 (no local USB target yet), stage 3 completes the 3-2-1 model.

**Old laptop drives:** considered for stage-2 storage, rejected. Unknown remaining lifespan, not 24/7-rated, too small individually, and the user's own instinct was "don't trust them for irreplaceable data long term," which is correct. They have possible roles as scratch / Jellyfin re-rippable content / retirement; they are not the primary photos-and-notes drive.

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
