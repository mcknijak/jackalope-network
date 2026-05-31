# homelab-server

Configuration and runbook for a single-box home server hosting Obsidian sync, photos (Immich), video (Jellyfin), and private chat (Matrix/Synapse).

The architecture, hardware recommendations, security posture, and decision log live in `docs/`. Start there if you want the why behind any of this:

- `docs/initial-plan.md`: full architecture overview, hardware list, cost breakdown
- `docs/decisions.md`: log of significant choices (federation, domain, encryption posture, etc.)
- `docs/security-audit.md`: full audit against the project's threat model, what's hardened, what's accepted gap
- `docs/encryption-at-rest.md`: where data is encrypted on disk and the post-reboot LUKS-unlock procedure
- `docs/networking.md`: how Tailscale, Caddy, and DNS fit together, written for someone new to the model
- `docs/why-tailscale.md`: why Tailscale-only instead of just app-level logins, with CVE evidence and middle-ground options (Funnel, Authelia)
- `docs/scaffolding-summary.md`: index of what got scaffolded and what was deferred

## Stack at a glance

- **OS:** Debian 12 server, no GUI
- **Containers:** Docker plus Docker Compose
- **Reverse proxy:** Caddy with the Porkbun DNS plugin for automatic wildcard TLS
- **Remote access:** Tailscale (everything is private to the tailnet by default)
- **Apps:** Immich (photos), Jellyfin (video), CouchDB plus Obsidian LiveSync (notes), Matrix/Synapse (chat with E2EE on by default), Element Web (Matrix client)
- **Welcome page:** static Vite build under `welcome/`, served by Caddy at the root of `jackalope.network`. Public-facing, links to the apps go dim when the visitor is off the tailnet.
- **Public surface:** the welcome page root and `photos.jackalope.network`, both via Tailscale Funnel. Everything else is tailnet-only.
- **Encryption at rest:** LUKS2 (Argon2id) on the `/mnt/data` mirror. OS NVMe is plaintext. See `docs/encryption-at-rest.md` for the trade-off.
- **Backups:** restic to a local USB drive nightly, to Backblaze B2 weekly. restic's own AES-256 encryption layer.

## Filesystem layout on the server

```
/srv/                         # all compose stacks live here
  caddy/
  immich/
  jellyfin/
  obsidian-couchdb/
  matrix/
  welcome/                    # source for the public welcome page; dist/ served by Caddy
/mnt/data/                    # the mirrored 8 TB HDDs, LUKS-encrypted
  immich/
    library/                  # photo originals
    postgres/                 # immich db
  jellyfin/
    movies/
    shows/
    music/
  couchdb/                    # obsidian sync db
  matrix/
    media/                    # synapse media store
    postgres/                 # synapse db
  backups/                    # local restic repo on the mirror (cache only)
/mnt/backup/                  # the external USB drive (primary local backup target)
  restic/
```

## Bootstrap order

These are the steps to go from a freshly imaged Debian box to a running stack.

1. Install Debian 12 to the NVMe. Create one user, add your SSH public key, enable SSH.
2. Copy this repo to the server: `git clone <repo> /srv/homelab-server` and symlink each stack directory into `/srv/` (or just clone into `/srv` and reference paths directly).
3. Run `bootstrap/debian-setup.sh` as root. This installs packages, hardens SSH, installs Docker, installs Tailscale, configures UFW, enables unattended security updates, and creates the external Docker network used by Caddy.
4. Run `tailscale up` interactively. Note the `100.x.x.x` address.
5. Plug in the two 8 TB drives. Find their device names with `lsblk`. Run `bootstrap/mdadm-mirror.sh /dev/sdX /dev/sdY`. The script will prompt whether to add LUKS encryption to the mirror; answer `y` (recommended) and pick a strong passphrase. See `docs/encryption-at-rest.md` for the post-reboot unlock procedure if you do.
6. Plug in the external USB backup drive. Format ext4, label it `homelab-backup`, mount at `/mnt/backup`. Add an `/etc/fstab` entry. (restic encrypts the snapshots themselves, so the underlying filesystem does not need LUKS.)
7. In Porkbun, point the relevant subdomains at the Tailscale IP:
   - `immich.jackalope.network` A `100.x.x.x`
   - `jellyfin.jackalope.network` A `100.x.x.x`
   - `couchdb.jackalope.network` A `100.x.x.x`
   - `matrix.jackalope.network` A `100.x.x.x`
   - `element.jackalope.network` A `100.x.x.x`
   - `probe.jackalope.network` A `100.x.x.x` (used by the welcome page to detect tailnet reachability)
   - `jackalope.network` (root) for now also A `100.x.x.x`; once Tailscale Funnel is set up (step 13), change this to a CNAME pointing at your machine's `<machine>.<tailnet>.ts.net` hostname so it's publicly reachable
   - `photos.jackalope.network` will be a CNAME to your Tailscale Funnel hostname later; leave it unset for now.
8. Generate a Porkbun API key pair (https://porkbun.com/account/api). Copy `caddy/.env.example` to `caddy/.env` and fill in the keys.
9. Build the welcome page so Caddy has something to serve at the root:
   ```bash
   # Easiest path: build on the server. Requires Node.
   curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
   sudo apt-get install -y nodejs
   cd /srv/welcome && npm ci && npm run build
   ```
   Alternative: build locally and `rsync welcome/dist/ jack@<tailnet-ip>:/srv/welcome/dist/`.
10. Bring up Caddy: `cd /srv/caddy && docker compose up -d`. Watch logs to confirm certs issue: `docker compose logs -f caddy`.
11. Bring up the apps in order. Each has its own README or notes:
    - `cd /srv/immich && cp .env.example .env`, edit, then `docker compose up -d`
    - `cd /srv/jellyfin && docker compose up -d`
    - `cd /srv/obsidian-couchdb && cp .env.example .env`, edit, `docker compose up -d`, then run `./configure-cors.sh`
    - `cd /srv/matrix`: follow `matrix/README.md` (one-time config generation, then `docker compose up -d`)
12. Have every Matrix user set up Secure Backup on first Element login. See `matrix/README.md` for the click-by-click. Rooms are E2EE by default, so losing device keys without backup means losing message history.
13. Set up Tailscale Funnel for public access to the photo share endpoint and the welcome page. Funnel does TCP passthrough to your local Caddy, so Caddy still terminates TLS with its own Let's Encrypt cert; no second daemon to manage, no Cloudflare account. See `docs/why-tailscale.md` for the Funnel-vs-Cloudflare-Tunnel comparison.
    - Enable Funnel for the node in the Tailscale admin console (https://login.tailscale.com/admin/acls -> nodeAttrs -> `funnel`).
    - On the server: `sudo tailscale serve --bg --https=443 tcp://localhost:443`, then `sudo tailscale funnel 443 on`. This forwards TLS-passthrough from the Funnel edge to your local Caddy on 443; Caddy sees the SNI and serves the right cert.
    - In Porkbun, CNAME `photos.jackalope.network` and `jackalope.network` (root) to your machine's Funnel hostname (`<machine>.<tailnet>.ts.net`).
    - Uncomment the `photos.jackalope.network` site block in `caddy/Caddyfile` and reload Caddy.
    - Verify from a device that is NOT on the tailnet: `curl -sI https://photos.jackalope.network` should return a valid 200 with a `jackalope.network` cert in the chain.
14. Install restic and set up backups:
    - `cp backups/restic.env.example /etc/restic.env`, fill in B2 creds and repo password
    - `cp backups/restic-backup.sh /usr/local/sbin/` and `chmod +x`
    - Copy the four systemd unit files to `/etc/systemd/system/`, then `systemctl enable --now restic-backup-usb.timer restic-backup-b2.timer`
    - Run the script once by hand against each repo to initialize it: `restic init` (USB and B2 separately).

## Day-to-day operations

- **Update everything:** `for d in /srv/*/; do (cd "$d" && docker compose pull && docker compose up -d); done`, then `apt update && apt upgrade -y`. About once a month.
- **Check disk health:** `smartctl -H /dev/sda /dev/sdb`. If `mdadm --detail /dev/md0` shows a degraded array, replace the failed drive.
- **Verify backups:** `restic -r /mnt/backup/restic snapshots`. Once a quarter, restore one file to `/tmp` to confirm the chain actually works.
- **Add a Matrix user:** see `matrix/README.md`. Registration is closed, so users are created by the operator with `register_new_matrix_user`.
- **Restart a single app:** `cd /srv/<app> && docker compose restart`.
- **Rebuild the welcome page:** `cd /srv/welcome && git pull && npm run build`. Caddy serves the new files on the next request, no restart needed.

## Recovery notes

- **Lost a HDD:** the mirror keeps serving. `mdadm --manage /dev/md0 --add /dev/sdZ` after replacing the drive. The rebuild takes hours. If LUKS is on, the mirror stays unlocked through a drive swap.
- **Lost the NVMe (OS drive):** reinstall Debian, re-run bootstrap, re-clone this repo, `mdadm --assemble --scan` finds the existing mirror, `cryptsetup open /dev/md0 data-crypt` unlocks (if LUKS), `mount /mnt/data`, then `docker compose up -d` per stack brings everything back. App state lives in `/mnt/data`, not on the NVMe.
- **Lost the whole box:** restore from B2 with `restic restore`. Snapshots include the Postgres dumps for Immich and Synapse, the CouchDB `_all_dbs` dumps, the Matrix media store, and Jellyfin metadata. Movie files themselves are not in B2 (too large); they're only on the local mirror plus USB.
- **Reboot procedure with LUKS:** see `docs/encryption-at-rest.md`. Every reboot needs a manual SSH-in to unlock `/mnt/data` before apps can start.

## Security posture

Full audit in `docs/security-audit.md`. Headlines:

- Threat model: targeted (someone wants *your* data) but not nation-state.
- Inbound from the internet: only Tailscale Funnel for `photos.jackalope.network` and the root welcome page. No ports forwarded on the Xfinity gateway.
- Inbound from the tailnet: SSH and all reverse-proxied apps. Apps that don't need to be tailnet-exposed (Postgres, Redis, internal Matrix federation) stay on internal Docker networks.
- SSH: key-only, root login disabled, fail2ban watching auth.log.
- Updates: `unattended-upgrades` for OS security patches. Container images pulled monthly by hand.
- Matrix federation: disabled at the server level, but rooms are created with `m.federate: true` to preserve the option to enable it later.
- Matrix E2EE: on by default for all new rooms. Bridges/bots that need plaintext can be created in opt-out rooms.
- `/mnt/data`: LUKS2 with Argon2id, manual unlock over SSH after each reboot.
- Backups: restic native AES-256 encryption with a passphrase distinct from LUKS.
