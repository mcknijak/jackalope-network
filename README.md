# homelab-server

Configuration and runbook for a single-box home server hosting Obsidian sync, photos (Immich), video (Jellyfin), and private chat (Matrix/Synapse).

The architecture, hardware recommendations, and decision log live in `docs/`. Start there if you want the why behind any of this:

- `docs/initial-plan.md`: full architecture overview, hardware list, cost breakdown
- `docs/decisions.md`: log of significant choices (federation, domain, etc.)

## Stack at a glance

- **OS:** Debian 12 server, no GUI
- **Containers:** Docker plus Docker Compose
- **Reverse proxy:** Caddy with the Porkbun DNS plugin for automatic wildcard TLS
- **Remote access:** Tailscale (everything is private to the tailnet by default)
- **Apps:** Immich (photos), Jellyfin (video), CouchDB plus Obsidian LiveSync (notes), Matrix/Synapse (chat), Element Web (Matrix client)
- **Public surface:** only `photos.jackalope.network`, via Cloudflare Tunnel, so Immich share links work for non-Tailscale recipients. Everything else is tailnet-only.
- **Backups:** restic to a local USB drive nightly, to Backblaze B2 weekly

## Filesystem layout on the server

```
/srv/                         # all compose stacks live here
  caddy/
  immich/
  jellyfin/
  obsidian-couchdb/
  matrix/
/mnt/data/                    # the mirrored 8 TB HDDs
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
5. Plug in the two 8 TB drives. Find their device names with `lsblk`. Run `bootstrap/mdadm-mirror.sh /dev/sdX /dev/sdY` to create the RAID1 mirror, format it ext4, and mount it at `/mnt/data` with the right subdirectories.
6. Plug in the external USB backup drive. Format ext4, label it `homelab-backup`, mount at `/mnt/backup`. Add an `/etc/fstab` entry.
7. In Porkbun, point the relevant subdomains at the Tailscale IP:
   - `immich.jackalope.network` A `100.x.x.x`
   - `jellyfin.jackalope.network` A `100.x.x.x`
   - `couchdb.jackalope.network` A `100.x.x.x`
   - `matrix.jackalope.network` A `100.x.x.x`
   - `element.jackalope.network` A `100.x.x.x`
   - `photos.jackalope.network` will be a CNAME to your Cloudflare Tunnel later; leave it unset for now.
8. Generate a Porkbun API key pair (https://porkbun.com/account/api). Copy `caddy/.env.example` to `caddy/.env` and fill in the keys.
9. Bring up Caddy: `cd /srv/caddy && docker compose up -d`. Watch logs to confirm certs issue: `docker compose logs -f caddy`.
10. Bring up the apps in order. Each has its own README or notes:
    - `cd /srv/immich && cp .env.example .env`, edit, then `docker compose up -d`
    - `cd /srv/jellyfin && docker compose up -d`
    - `cd /srv/obsidian-couchdb && cp .env.example .env`, edit, `docker compose up -d`, then run `./configure-cors.sh`
    - `cd /srv/matrix`: follow `matrix/README.md` (one-time config generation, then `docker compose up -d`)
11. Set up the public Immich tunnel: install `cloudflared`, run `cloudflared tunnel login`, create a tunnel named `homelab`, route `photos.jackalope.network` to `http://localhost:80` (Caddy), and run `cloudflared` as a systemd service. Add a `photos.jackalope.network` site block in the Caddyfile pointing at `immich-server:2283`.
12. Install restic and set up backups:
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

## Recovery notes

- **Lost a HDD:** the mirror keeps serving. `mdadm --manage /dev/md0 --add /dev/sdZ` after replacing the drive. The rebuild takes hours.
- **Lost the NVMe (OS drive):** reinstall Debian, re-run bootstrap, re-clone this repo, `mdadm --assemble --scan` will find the existing mirror, `mount -a` mounts it, then `docker compose up -d` per stack brings everything back. App state lives in `/mnt/data`, not on the NVMe.
- **Lost the whole box:** restore from B2 with `restic restore`. Snapshots include the Postgres dumps for Immich and Synapse, the CouchDB `_all_dbs` dumps, the Matrix media store, and Jellyfin metadata. Movie files themselves are not in B2 (too large); they're only on the local mirror plus USB.

## Security posture

- Inbound from the internet: only the Cloudflare Tunnel for `photos.jackalope.network`. No ports forwarded on the Xfinity gateway.
- Inbound from the tailnet: SSH and all reverse-proxied apps. Apps that don't need to be tailnet-exposed (Postgres, Redis, internal Matrix federation) stay on internal Docker networks.
- SSH: key-only, root login disabled, fail2ban watching auth.log.
- Updates: `unattended-upgrades` for OS security patches. Container images pulled monthly by hand.
- Matrix federation: disabled at the server level, but rooms are created with `m.federate: true` to preserve the option to enable it later.
