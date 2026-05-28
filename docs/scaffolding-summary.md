# Scaffolding Summary

Snapshot of what was generated when the repo was first scaffolded on 2026-05-28. Use this as a quick index of what each file is for, and as a record of what was intentionally left out of the initial pass.

27 files across 6 stacks plus bootstrap, backups, and docs. All files are free of em dashes and use American English, per the standing writing-style rules.

## What landed in the repo

### Bootstrap and root

- `README.md`: top-level runbook covering the full bootstrap order, daily operations, and recovery scenarios
- `.gitignore`: excludes `.env`, secrets, data dirs, and Caddy build artifacts
- `bootstrap/debian-setup.sh`: idempotent Debian setup (packages, SSH hardening, UFW, Docker, Tailscale, shared `proxy` Docker network)
- `bootstrap/mdadm-mirror.sh`: interactive RAID1 plus ext4 plus fstab setup, creates all per-app subdirectories under `/mnt/data`

### Caddy

- Custom `Dockerfile` that builds Caddy with the `caddy-dns/porkbun` plugin
- `compose.yml` joined to the external `proxy` network
- `Caddyfile` with one site block per app, using DNS-01 via Porkbun (works fine with no inbound ports open)
- `.env.example` for the two Porkbun API keys

### Immich, Jellyfin, Obsidian/CouchDB, Matrix

- Each app has its own `compose.yml` and (where needed) `.env.example`
- Jellyfin includes `/dev/dri` passthrough and `group_add` for Intel QuickSync
- Obsidian/CouchDB ships a `configure-cors.sh` that does the CouchDB API dance the LiveSync plugin requires, plus a README for the plugin setup
- Matrix includes Synapse, Postgres, and Element Web in one stack, plus `homeserver.yaml.example`, `element-config.json`, and a README with the user-registration commands and the future-federation steps

### Backups

- `restic-backup.sh` dispatches on `usb` or `b2`, runs `pg_dump` against both Postgres databases first, snapshots the CouchDB DB list, then backs up `/mnt/data`, `/srv`, and the dumps to the chosen repo
- Four systemd units: nightly USB timer, weekly B2 timer
- `restic.env.example` for the encryption password and B2 credentials
- A README walking through install, verification, single-file restore, single-database restore, and full disaster recovery

## Things deliberately deferred

These were left out of the initial scaffolding pass. The reasoning is captured here so future-me knows whether to revisit them.

- **Cloudflare Tunnel for `photos.jackalope.network`.** Documented in the top-level README as step 11 and as a commented site block in the `Caddyfile`. Worth standing up once the rest of the stack is healthy, not before, since it's the one piece that intentionally widens the public attack surface.
- **Image tag pinning.** Most stacks use `:latest` or release-channel tags rather than digests. For a homelab that prioritizes "easy to pull updates monthly" over "byte-for-byte reproducibility," that's the right trade. The Immich Postgres tag is a fixed version because the project ties data format to it; the README notes to compare against upstream when pulling.
- **Monitoring.** Nothing in here exports metrics or pages on failure. A fine v2 would be a small Uptime Kuma container behind Caddy. That would cover about 95% of the practical "is anything down" question without the complexity of Prometheus + Grafana.

## What to do before the hardware arrives

Only three things are useful to do before the box is in hand:

1. Buy the box (refurb Dell OptiPlex 7060 SFF or equivalent), two 8 TB drives, and one USB backup drive.
2. Create the Porkbun API key pair at https://porkbun.com/account/api and toggle API access on `jackalope.network` in the domain list, so the credentials are ready to paste into `caddy/.env`.
3. Decide on a hostname for the box (default in the bootstrap script is `jackalope`) and a Linux username (default `jack`). Edit those at the top of `bootstrap/debian-setup.sh` if you want different values.
