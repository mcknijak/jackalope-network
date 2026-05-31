# Scaffolding Summary

Snapshot of what was generated when the repo was first scaffolded on 2026-05-28, plus the security and welcome-page additions in the second scaffolding pass on the same date. Use this as a quick index of what each file is for, and as a record of what was intentionally left out.

All files are free of em dashes and use American English, per the standing writing-style rules.

## What landed in the repo

### Bootstrap and root

- `README.md`: top-level runbook covering the full bootstrap order, daily operations, and recovery scenarios
- `.gitignore`: excludes `.env`, secrets, data dirs, Caddy build artifacts, and the welcome page's `node_modules` plus `dist/`
- `bootstrap/debian-setup.sh`: idempotent Debian setup (packages, SSH hardening, UFW, Docker, Tailscale, shared `proxy` Docker network)
- `bootstrap/mdadm-mirror.sh`: interactive RAID1 plus optional LUKS2 (Argon2id) plus ext4 plus fstab/crypttab setup, creates all per-app subdirectories under `/mnt/data`

### Caddy

- Custom `Dockerfile` that builds Caddy with the `caddy-dns/porkbun` plugin
- `compose.yml` joined to the external `proxy` network; bind-mounts `/srv/welcome/dist` read-only so Caddy can serve the welcome page directly
- `Caddyfile` with one site block per app, plus the public `jackalope.network` root (welcome page) and `probe.jackalope.network` (tailnet-only probe endpoint with CORS headers for the welcome page), all using DNS-01 via Porkbun
- `.env.example` for the two Porkbun API keys

### Immich, Jellyfin, Obsidian/CouchDB, Matrix

- Each app has its own `compose.yml` and (where needed) `.env.example`
- Jellyfin includes `/dev/dri` passthrough and `group_add` for Intel QuickSync
- Obsidian/CouchDB ships a `configure-cors.sh` that does the CouchDB API dance the LiveSync plugin requires, plus a README for the plugin setup
- Matrix includes Synapse, Postgres, and Element Web in one stack
- `matrix/homeserver.yaml.example` is hardened: E2EE on by default for new rooms, `url_preview_ip_range_blacklist` covering RFC1918/CGNAT/link-local/loopback, tightened login and message rate limits, `registration_requires_token: true` as belt-and-suspenders even though registration is disabled
- `matrix/README.md` has the user-registration commands, the Secure Backup setup procedure every user has to do on first login, and the future-federation steps

### Welcome page

- `welcome/`: React + Vite project that builds a single-page public landing for `jackalope.network`
- Tokyo Night palette and FiraCode type mirroring the portfolio at jackmcknight.dev
- Hero block with bio, tile grid for each app, light/dark theme toggle, footer
- `src/hooks/useTailnetProbe.js` does a client-side fetch against `probe.jackalope.network/ok`; on success the tiles are live, on failure they render dimmed with a "tailnet only" badge
- `welcome/README.md` with local dev, build, and deploy paths (build-on-server vs build-on-laptop-then-rsync)
- Output `dist/` is gitignored

### Backups

- `restic-backup.sh` dispatches on `usb` or `b2`, runs `pg_dump` against both Postgres databases first, snapshots the CouchDB DB list, then backs up `/mnt/data`, `/srv`, and the dumps to the chosen repo
- Four systemd units: nightly USB timer, weekly B2 timer
- `restic.env.example` for the encryption password and B2 credentials
- A README walking through install, verification, single-file restore, single-database restore, and full disaster recovery

### Docs

- `docs/initial-plan.md`: original architecture/hardware/cost plan
- `docs/decisions.md`: running log of significant choices
- `docs/security-audit.md`: audit against threat model (b), what's hardened, what's accepted gap, quarterly verification routine, incident-response notes
- `docs/encryption-at-rest.md`: layer-by-layer table of what's encrypted, the post-reboot LUKS unlock procedure, passphrase management, and the Dropbear-over-Tailscale upgrade path
- `docs/networking.md`: from-scratch explanation of how Tailscale, Caddy, and DNS fit together, written for someone new to the model
- `docs/scaffolding-summary.md`: this file

## Things deliberately deferred

These were left out of the initial scaffolding pass. The reasoning is captured here so future-me knows whether to revisit them.

- **Full-disk encryption on the OS NVMe.** Documented in `docs/encryption-at-rest.md`. LUKS on the boot disk forces an interactive unlock at every reboot, which on this hardware means either a console or Dropbear-in-initramfs. The OS disk holds rotatable credentials but no user data, so the threat-model trade favors plain NVMe plus LUKS on `/mnt/data`. Upgrade path is documented.
- **Tailscale Funnel for `photos.jackalope.network` and for the root welcome page.** Decision moved from Cloudflare Tunnel to Funnel after the access-model review (see `docs/why-tailscale.md`). Documented in the top-level README as step 13 and as a commented site block in the `Caddyfile`. Worth standing up once the rest of the stack is healthy. Until then the welcome page is reachable only on the tailnet, which is fine for testing.
- **Image tag pinning.** Most stacks use `:latest` or release-channel tags rather than digests. For a homelab that prioritizes "easy to pull updates monthly" over "byte-for-byte reproducibility," that's the right trade. The Immich Postgres tag is a fixed version because the project ties data format to it; the README notes to compare against upstream when pulling.
- **Monitoring.** Nothing in here exports metrics or pages on failure. A fine v2 would be a small Uptime Kuma container behind Caddy. That would cover about 95% of the practical "is anything down" question without the complexity of Prometheus + Grafana.
- **Tailnet lock (Tailscale's signed-device feature).** Mitigates Tailscale-coordination-plane compromise. Setup is non-trivial and the threat is low; revisit if the tailnet grows or if the security audit is upgraded to threat model (c).
- **Per-app egress firewalling, image signing, SIEM, hardware SSH keys.** Considered in the security audit and explicitly accepted as out of scope for this threat model. See `docs/security-audit.md` for the reasoning.

## What to do before the hardware arrives

Only four things are useful to do before the box is in hand:

1. Buy the box (refurb Dell OptiPlex 7060 SFF or equivalent), two 8 TB drives, and one USB backup drive.
2. Create the Porkbun API key pair at https://porkbun.com/account/api and toggle API access on `jackalope.network` in the domain list, so the credentials are ready to paste into `caddy/.env`.
3. Decide on a hostname for the box (default in the bootstrap script is `jackalope`) and a Linux username (default `jack`). Edit those at the top of `bootstrap/debian-setup.sh` if you want different values.
4. Pick the LUKS and restic passphrases now and store them in your password manager (and print a backup copy for a physical safe). You will need both during bootstrap and you do not want to be picking strong passphrases under time pressure.
