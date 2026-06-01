# homelab-server

Configuration and runbook for a single-box home server hosting Obsidian sync, photos (Immich), video (Jellyfin), private chat (Matrix/Synapse), an ebook library (Calibre-Web), audiobooks plus podcasts (Audiobookshelf), a document archive (Paperless-ngx), and container management (Portainer).

The architecture, hardware recommendations, security posture, and decision log live in `docs/`. Start there if you want the why behind any of this:

- `docs/staged-rollout.md`: the three-stage lifecycle (PC only -> + drive + B2 -> + mirror + full backup). Read this first if you're building from scratch; the rest of the docs describe the stage-3 end state
- `docs/initial-plan.md`: full architecture overview, hardware list, cost breakdown (historical scaffolding, stage-3 design)
- `docs/decisions.md`: log of significant choices (federation, domain, encryption posture, etc.)
- `docs/security-audit.md`: full audit against the project's threat model, what's hardened, what's accepted gap
- `docs/encryption-at-rest.md`: where data is encrypted on disk and the post-reboot LUKS-unlock procedure
- `docs/networking.md`: how Tailscale, Caddy, and DNS fit together, written for someone new to the model
- `docs/why-tailscale.md`: why Tailscale-only instead of just app-level logins, with CVE evidence and middle-ground options (Funnel, Authelia)
- `docs/scaffolding-summary.md`: index of what got scaffolded and what was deferred

**Reading order if you're new:** `docs/staged-rollout.md` for the lifecycle, then `docs/decisions.md` for the why behind the bigger calls, then the bootstrap order below (which targets the stage-3 end state and is what you'll actually run when you get there).

## Stack at a glance

- **OS:** Debian 13 (Trixie) server, no GUI
- **Containers:** Docker plus Docker Compose
- **Reverse proxy:** Caddy with the Porkbun DNS plugin for automatic wildcard TLS
- **Remote access:** Tailscale (everything is private to the tailnet by default)
- **Apps:** Immich (photos), Jellyfin (video), CouchDB plus Obsidian LiveSync (notes), Matrix/Synapse (chat with E2EE on by default), Element Web (Matrix client), Calibre-Web (ebooks), Audiobookshelf (audiobooks plus podcasts), Paperless-ngx (document archive), Portainer CE (container management UI)
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
  ebooks/                     # Calibre-Web
  spokenword/                 # Audiobookshelf (audiobooks + podcasts)
  cabinet/                    # Paperless-ngx (stage 2+)
  portainer/                  # Portainer CE + local agent
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
  ebooks/
    library/                  # calibre library directory (metadata.db + book files)
    config/                   # calibre-web's own state (admin user, reading state)
  spokenword/
    audiobooks/
    podcasts/
    metadata/                 # audiobookshelf metadata
    config/                   # audiobookshelf config db
  cabinet/                    # stage 2+ only
    data/                     # paperless internal data
    media/                    # ocr'd documents
    consume/                  # watched folder for new docs
    export/                   # paperless export staging
    postgres/                 # paperless db
  portainer/
    data/                     # portainer config db
  backups/                    # local restic repo on the mirror (cache only)
/mnt/backup/                  # the external USB drive (primary local backup target)
  restic/
```

## Bootstrap order

These are the steps to go from a freshly imaged Debian box to a running stack.

> **Stage scope:** the order below is the stage-3 path (full mirror + USB backup + B2). Read `docs/staged-rollout.md` first; it tells you which of these steps to do at stage 1 vs stage 2 vs stage 3. The inline `[stage X]` tags below mark which step belongs to which stage. Steps with no tag apply at every stage.

1. **[all stages]** Install Debian 13 (Trixie) to the NVMe. Create one user, add your SSH public key, enable SSH.
2. **[all stages]** Copy this repo to the server: `git clone <repo> /srv/homelab-server` and symlink each stack directory into `/srv/` (or just clone into `/srv` and reference paths directly).
3. **[all stages]** Run `bootstrap/debian-setup.sh` as root. This installs packages, hardens SSH, installs Docker, installs Tailscale, configures UFW, enables unattended security updates, and creates the external Docker network used by Caddy. The script's "Next steps" echo at the end branches by stage.
4. **[all stages]** Run `tailscale up` interactively. Note the `100.x.x.x` address.
5. **[stage 3 only]** Plug in the two NAS drives. Find their device names with `lsblk`. Run `bootstrap/mdadm-mirror.sh /dev/sdX /dev/sdY`. The script will prompt whether to add LUKS encryption to the mirror; answer `y` (recommended) and pick a strong passphrase. See `docs/encryption-at-rest.md` for the post-reboot unlock procedure if you do. **At stage 1**, instead create the per-app directories on the OS disk: `sudo mkdir -p /mnt/data/{immich/library,immich/postgres,jellyfin/movies,jellyfin/shows,jellyfin/music,couchdb/data,couchdb/config,matrix/synapse,matrix/postgres,matrix/media,backups}` and `chown` them to your user. **At stage 2**, plug in and LUKS-format the single stage-2 drive, mount it at `/mnt/data`, then run the same `mkdir`.
6. **[stage 3 only]** Plug in the external USB backup drive. Format ext4, label it `homelab-backup`, mount at `/mnt/backup`. Add an `/etc/fstab` entry. (restic encrypts the snapshots themselves, so the underlying filesystem does not need LUKS.) **At stages 1 and 2 there is no separate USB backup drive yet.**
7. In Porkbun, set the DNS records. Which ones to set depends on the stage.

   **[all stages]** Tailnet-only subdomains, A record to the server's `100.x.x.x` Tailscale IP:
   - `immich.jackalope.network` A `100.x.x.x`
   - `jellyfin.jackalope.network` A `100.x.x.x`
   - `couchdb.jackalope.network` A `100.x.x.x`
   - `matrix.jackalope.network` A `100.x.x.x`
   - `element.jackalope.network` A `100.x.x.x`
   - `shelf.jackalope.network` A `100.x.x.x` (Calibre-Web; stage 1+)
   - `spokenword.jackalope.network` A `100.x.x.x` (Audiobookshelf; stage 1+)
   - `portainer.jackalope.network` A `100.x.x.x` (Portainer; stage 1+)
   - `cabinet.jackalope.network` A `100.x.x.x` (Paperless-ngx; **stage 2+ only**)
   - `probe.jackalope.network` A `100.x.x.x` (used by the welcome page to detect tailnet reachability)

   **[stage 1 with Netlify-hosted welcome page]** The apex `jackalope.network` stays pointed at Netlify (CNAME / ALIAS / ANAME to your Netlify site, per the Netlify "Domain settings" instructions). Do not set the photos host yet, there is nothing public to share. The visitor still sees the welcome page from Netlify; the tile probe fails and the tiles render dimmed, which is the correct stage-1 behavior.

   **[stage 1+ when you cut welcome page from Netlify to the box, OR stage 2+]** Apex CNAME to Funnel:
   - `jackalope.network` (root) CNAME to your machine's `<machine>.<tailnet>.ts.net` hostname (see step 13 for the Funnel setup that makes this hostname reachable).

   **[whenever you want to share Immich albums publicly]** Photos host CNAME to Funnel:
   - `photos.jackalope.network` CNAME to your machine's `<machine>.<tailnet>.ts.net` hostname.
8. Generate a Porkbun API key pair (https://porkbun.com/account/api). Copy `caddy/.env.example` to `caddy/.env` and fill in the keys.
9. Build the welcome page so Caddy has something to serve at the root.

   **[stage 1 if you're still on Netlify]** Optional: build on the server only if you want the welcome page reachable on the tailnet directly (`https://jackalope.network` resolves to Netlify publicly but a tailnet-only build at the same path lets in-tailnet visitors hit the server copy). For most stage-1 setups you can skip this step entirely; the public welcome page lives on Netlify and the tailnet-only subdomains are what people on the tailnet actually use.

   **[any stage where the welcome page lives on the box]** Build on the server:
   ```bash
   # Easiest path: build on the server. Requires Node.
   curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
   sudo apt-get install -y nodejs
   cd /srv/welcome && npm ci && npm run build
   ```
   Alternative: build locally and `rsync welcome/dist/ jack@<tailnet-ip>:/srv/welcome/dist/`.
10. Bring up Caddy: `cd /srv/caddy && docker compose up -d`. Watch logs to confirm certs issue: `docker compose logs -f caddy`.
11. Bring up the apps in order. Each has its own README or notes. The first four run at every stage; the last is stage 2+:
    - `cd /srv/immich && cp .env.example .env`, edit, then `docker compose up -d`
    - `cd /srv/jellyfin && docker compose up -d`
    - `cd /srv/obsidian-couchdb && cp .env.example .env`, edit, `docker compose up -d`, then run `./configure-cors.sh`
    - `cd /srv/matrix`: follow `matrix/README.md` (one-time config generation, then `docker compose up -d`)
    - `cd /srv/ebooks && docker compose up -d` then open `https://shelf.jackalope.network` and complete the first-run wizard (see `ebooks/README.md`)
    - `cd /srv/spokenword && docker compose up -d` then open `https://spokenword.jackalope.network` and complete the first-run wizard (see `spokenword/README.md`)
    - `cd /srv/portainer && docker compose up -d` then open `https://portainer.jackalope.network` **within 5 minutes** to set the admin password (see `portainer/README.md` for the trust-boundary callout)
    - **[stage 2+ only]** `cd /srv/cabinet && cp .env.example .env`, generate `PAPERLESS_DB_PASS` and `PAPERLESS_SECRET_KEY` (`openssl rand -hex 24` and `openssl rand -hex 50`), `docker compose up -d`, then `docker compose exec paperless python3 manage.py createsuperuser` to create the first login. Full setup including the Porkbun mailbox and the IMAP whitelist rules is in `cabinet/README.md`.
12. Have every Matrix user set up Secure Backup on first Element login. See `matrix/README.md` for the click-by-click. Rooms are E2EE by default, so losing device keys without backup means losing message history.
13. **[needed only when you actually want public ingress]** Set up Tailscale Funnel for public access to the photo share endpoint and / or the welcome page. Not needed at stage 1 if the welcome page is on Netlify and you have no public photo sharing yet. Become needed when either (a) you cut the welcome page over from Netlify to the box, or (b) you want to share an Immich album publicly via link. Funnel does TCP passthrough to your local Caddy, so Caddy still terminates TLS with its own Let's Encrypt cert; no second daemon to manage, no Cloudflare account. See `docs/why-tailscale.md` for the Funnel-vs-Cloudflare-Tunnel comparison.
    - Enable Funnel for the node in the Tailscale admin console (https://login.tailscale.com/admin/acls -> nodeAttrs -> `funnel`).
    - On the server: `sudo tailscale serve --bg --https=443 tcp://localhost:443`, then `sudo tailscale funnel 443 on`. This forwards TLS-passthrough from the Funnel edge to your local Caddy on 443; Caddy sees the SNI and serves the right cert.
    - In Porkbun, CNAME `photos.jackalope.network` and `jackalope.network` (root) to your machine's Funnel hostname (`<machine>.<tailnet>.ts.net`).
    - Uncomment the `photos.jackalope.network` site block in `caddy/Caddyfile` and reload Caddy.
    - Verify from a device that is NOT on the tailnet: `curl -sI https://photos.jackalope.network` should return a valid 200 with a `jackalope.network` cert in the chain.
14. **[stage 2: B2 only; stage 3: both]** Install restic and set up backups:
    - `cp backups/restic.env.example /etc/restic.env`, fill in B2 creds and repo password
    - `cp backups/restic-backup.sh /usr/local/sbin/` and `chmod +x`
    - **At stage 3:** copy all four systemd unit files to `/etc/systemd/system/`, then `systemctl enable --now restic-backup-usb.timer restic-backup-b2.timer`. Run the script once by hand against each repo to initialize: `restic init` (USB and B2 separately).
    - **At stage 2:** copy only the two B2 unit files (`restic-backup-b2.service` and `restic-backup-b2.timer`); skip the USB pair. `systemctl enable --now restic-backup-b2.timer`. Init the B2 repo only.

## Day-to-day operations

- **[all stages] Update everything:** `for d in /srv/*/; do (cd "$d" && docker compose pull && docker compose up -d); done`, then `apt update && apt upgrade -y`. About once a month.
- **[stage 1] Check disk health:** `smartctl -H /dev/sdX` against whatever single drive holds your data (typically the factory HDD, sometimes the NVMe if the box came NVMe-only).
- **[stage 2] Check disk health:** `smartctl -H` against the OS NVMe and the stage-2 data drive.
- **[stage 3] Check disk health and mirror state:** `smartctl -H /dev/sda /dev/sdb`. If `mdadm --detail /dev/md0` shows a degraded array, replace the failed drive.
- **[stage 2: B2 only; stage 3: USB and B2] Verify backups:** `restic -r <repo> snapshots`. Once a quarter, restore one file to `/tmp` to confirm the chain actually works. (At stage 1 there are no backups; the verification is "the upstream service still has my data," which you should sanity-check the same way.)
- **[all stages] Add a Matrix user:** see `matrix/README.md`. Registration is closed, so users are created by the operator with `register_new_matrix_user`.
- **[all stages] Restart a single app:** `cd /srv/<app> && docker compose restart`.
- **[all stages] Rebuild the welcome page:** `cd /srv/welcome && git pull && npm run build`. Caddy serves the new files on the next request, no restart needed. (Only applicable when the welcome page is served from the box, which at stage 1 may be Netlify instead.)

## Recovery notes

- **[stage 1] Lost the data drive:** there is no recovery from the box itself. Restore is reconstruction from the upstream sources: re-sync photos from iCloud / Google Photos into a fresh Immich, re-clone the Obsidian vault from your laptop into a fresh CouchDB, re-rip media into a fresh Jellyfin library, re-import EPUBs and PDFs from your laptop's Calibre library into a fresh Calibre-Web, re-add audiobook source files and re-subscribe podcast feeds in a fresh Audiobookshelf, redeploy Portainer (set a new admin password; managed Docker resources are untouched). Accept loss of any Matrix history and any Audiobookshelf listening progress that existed only on the homelab. Cabinet does not run at stage 1 so there is nothing to lose. This is the explicit risk accepted at stage 1 (see `docs/staged-rollout.md`). Plan accordingly: stage 1 is for evaluating, not for archival.
- **[stage 2] Lost the stage-2 data drive:** restore from B2 with `restic restore`. Snapshots include Postgres dumps for Immich, Synapse, and Paperless; the CouchDB `_all_dbs` dump; Immich originals; the Matrix media store; the ebook library; the audiobook and podcast libraries; the Paperless data, media, consume, and Postgres directories; the Portainer config; and `/srv`. Jellyfin media is not in B2 and is reacquired from source.
- **[stage 3] Lost a HDD:** the mirror keeps serving. `mdadm --manage /dev/md0 --add /dev/sdZ` after replacing the drive. The rebuild takes hours. If LUKS is on, the mirror stays unlocked through a drive swap.
- **[stage 3] Lost the NVMe (OS drive):** reinstall Debian, re-run bootstrap, re-clone this repo, `mdadm --assemble --scan` finds the existing mirror, `cryptsetup open /dev/md0 data-crypt` unlocks (if LUKS), `mount /mnt/data`, then `docker compose up -d` per stack brings everything back. App state lives in `/mnt/data`, not on the NVMe.
- **[stage 3] Lost the whole box:** restore from B2 with `restic restore`. Snapshots include the Postgres dumps for Immich, Synapse, and Paperless; the CouchDB `_all_dbs` dump; the Matrix media store; the ebook library; the audiobook and podcast libraries; the Paperless data, media, and consume directories; the Portainer config; and `/srv`. Movie files themselves are not in B2 (too large); they're only on the local mirror plus USB.
- **[stage 2 and stage 3] Reboot procedure with LUKS:** see `docs/encryption-at-rest.md`. Every reboot needs a manual SSH-in to unlock the LUKS volume before apps can start. (At stage 2 the device path is the stage-2 drive, not `/dev/md0`.) At stage 1 there is no LUKS, so reboot is unattended.

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
