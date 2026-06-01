# ebooks (Calibre-Web)

Web reader and OPDS endpoint for an EPUB / PDF library, served at `shelf.jackalope.network` on the tailnet.

> **Stage scope:** runs at every stage. At stage 1 the library lives at `/mnt/data/ebooks/library` on the OS disk; at stage 2 on the single LUKS-encrypted data drive; at stage 3 on the LUKS-encrypted RAID1 mirror. Backed up by restic starting at stage 2 (B2 weekly) and stage 3 (USB nightly + B2 weekly). At stage 1 there is no backup; treat the library as a convenience copy and keep the canonical files wherever you currently store them.

## What it is

[Calibre-Web](https://github.com/janeczku/calibre-web) is a Flask front end over a Calibre library directory. It does:

- A clean in-browser EPUB / PDF reader (good enough that "phone Safari" is a fine reading device).
- An [OPDS](https://en.wikipedia.org/wiki/Open_Publication_Distribution_System) feed at `/opds`, which iOS reader apps can subscribe to so the whole library is browsable and downloadable on the device.
- Format conversion (EPUB <-> MOBI <-> AZW3 etc.), via the bundled Calibre binaries (`DOCKER_MODS=linuxserver/mods:universal-calibre` in `compose.yml`).
- Optional send-to-Kindle / send-by-email, if you wire up SMTP. Not configured in the scaffolding; add it later if you ever want a Kindle in the loop.

It does **not** include the full Calibre desktop app. If you want to do heavy library management (mass tagging, complex metadata fixes) you can run desktop Calibre on your laptop, point it at the library directory over SSH / rsync, and Calibre-Web will pick up the changes on the next library refresh.

## First-time setup

1. Create the library and config directories:

   ```bash
   mkdir -p /mnt/data/ebooks/{library,config}
   ```

2. Bring up the stack:

   ```bash
   cd /srv/ebooks && docker compose up -d
   ```

3. Open `https://shelf.jackalope.network` from a tailnet device. The first-run wizard asks you to:
   - Set the library path (use `/books`, which is the container path mapped to `/mnt/data/ebooks/library`).
   - Create the admin account. **Default credentials are `admin` / `admin123`. Change them immediately**, before the first OPDS poll.
   - Optionally enable user registration. Leave this off.

4. Add books. Two paths:
   - **Upload via the web UI**, which works fine for a handful of files at a time.
   - **Drop files into `/mnt/data/ebooks/library` directly**, then in Calibre-Web hit Admin -> "Reconnect to Calibre Library." Use this for an initial bulk import.

   Calibre-Web stores the library's metadata in `metadata.db` inside the library directory. On a truly fresh install (no existing Calibre library at all), Calibre-Web creates an empty `metadata.db` automatically on first start.

## iOS reading

Browser-first is fine for most cases; Calibre-Web's reader works in mobile Safari. For offline reading or a more native experience, point an OPDS-capable reader at `https://shelf.jackalope.network/opds`:

- **KyBook 3** (paid, ~$5, mature, the most-recommended option): Settings -> OPDS catalogs -> Add, URL above, your Calibre-Web username and password.
- **PocketBook Reader** (free): same setup, slightly less polished.

You may need to use the auth-in-URL form for some readers: `https://<user>:<password>@shelf.jackalope.network/opds`.

## Things to know

- **`DOCKER_MODS=linuxserver/mods:universal-calibre`** in `compose.yml` pulls the Calibre binaries into the container so format conversion works. Without it, you can read in the browser but cannot convert formats or use send-to-Kindle. The image is a few hundred MB larger as a result.
- **Reading progress per device is local to each reader app.** Calibre-Web tracks "read / unread / shelved" at the library level, not page-level sync across devices.
- **Permissions.** The compose file runs the container as `PUID=1000:PGID=1000`, which is the default `jack` user from the bootstrap script. If you ever change the host user, update both values.
- **Backups.** Everything Calibre-Web cares about (the library files, `metadata.db`, the app's own config DB with admin user / UI settings / reading state) sits under `/mnt/data/ebooks/`, so restic captures the whole thing at stage 2+. A restore is a single `restic restore` plus `docker compose up -d` with no manual reconfiguration needed.
