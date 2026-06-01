# Backups

Two restic repositories: a local one on an external USB drive (nightly), and a remote one on Backblaze B2 (weekly). Both use the same passphrase so a single password unlocks any snapshot.

> **Stage scope:** the two-repo setup below is the stage-3 end state. Stage 1 has no backups at all (data is reconstructable from upstream services; see `docs/staged-rollout.md`). Stage 2 enables only the B2 repo, since there is no local USB drive yet at that stage. In the install steps below, the USB-repo init and the USB systemd timer are stage-3-only; the B2-repo init and the B2 systemd timer apply at stage 2 and stage 3 unchanged.

## What gets backed up

- `/mnt/data/immich` (photo originals plus the Immich Postgres data directory)
- `/mnt/data/couchdb` (raw CouchDB files)
- `/mnt/data/matrix` (Synapse media store plus Postgres data directory)
- `/mnt/data/ebooks` (library files, `metadata.db`, Calibre-Web's own config DB)
- `/mnt/data/spokenword` (audiobook files, podcast episodes, metadata, config). Per the decision to treat these as Obsidian-class, the media files themselves go to backup, not just the metadata.
- `/mnt/data/cabinet` (Paperless data, OCR'd media, consume queue, export directory, Postgres data directory). Stage 2+ only; the path does not exist before stage 2 and restic skips it cleanly.
- `/mnt/data/portainer` (Portainer config DB: admin users, environment definitions, custom templates)
- `/srv` (all compose files, env files, Caddyfile, configure-cors.sh, etc.)
- A temp directory containing:
  - `immich.pgdump`: logical Postgres dump of the Immich database
  - `synapse.pgdump`: logical Postgres dump of the Synapse database
  - `paperless.pgdump`: logical Postgres dump of the Paperless database (stage 2+ only; skipped if the container isn't running)
  - `couch-all-dbs.json`: list of CouchDB databases at backup time

The Postgres dumps are belt-and-suspenders. The raw `pg_data` directories under `/mnt/data` are also captured, but a logical dump is easier to selectively restore and is portable across major Postgres versions.

## What does NOT get backed up

- `/mnt/data/jellyfin` (movies, shows, music). These can be re-acquired and would dominate the B2 bill. If you want them protected, add a second cheap external drive and `rsync` to it on its own schedule.
- Docker images themselves. They're reproducible from the compose files.
- Redis state for Paperless (the `paperless_redis` Docker volume). Redis here is a job queue cache only; loss means in-flight consume jobs re-run, not data loss.

## Install

Steps 1, 2, and 3a are the same at stage 2 and stage 3. Step 3b, the systemd units, and the smoke test differ by stage.

```bash
# 1. Copy the script to the system path  [stage 2 and stage 3]
sudo cp restic-backup.sh /usr/local/sbin/restic-backup.sh
sudo chmod 750 /usr/local/sbin/restic-backup.sh
sudo chown root:root /usr/local/sbin/restic-backup.sh

# 2. Write the credentials file  [stage 2 and stage 3]
sudo cp restic.env.example /etc/restic.env
sudo chmod 600 /etc/restic.env
sudo chown root:root /etc/restic.env
# edit /etc/restic.env:
#   stage 2: set RESTIC_PASSWORD and the B2 keys; the USB repo path can be left empty
#   stage 3: set everything (RESTIC_PASSWORD, B2 keys, USB and B2 repo paths)

# 3a. Initialize the B2 repository (one-time)  [stage 2 and stage 3]
sudo -E bash -c 'set -a; source /etc/restic.env; set +a; \
  RESTIC_REPOSITORY="$RESTIC_REPOSITORY_B2" restic init'

# 3b. Initialize the USB repository (one-time)  [stage 3 only]
sudo -E bash -c 'set -a; source /etc/restic.env; set +a; \
  RESTIC_REPOSITORY="$RESTIC_REPOSITORY_USB" restic init'

# 4. Install systemd units
#   stage 2 (B2 only):
sudo cp restic-backup-b2.service restic-backup-b2.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now restic-backup-b2.timer

#   stage 3 (both USB and B2):
sudo cp restic-backup-usb.service restic-backup-usb.timer \
        restic-backup-b2.service  restic-backup-b2.timer \
        /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now restic-backup-usb.timer restic-backup-b2.timer

# 5. Test by running the script once manually
#   stage 2:
sudo /usr/local/sbin/restic-backup.sh b2
#   stage 3:
sudo /usr/local/sbin/restic-backup.sh usb
sudo /usr/local/sbin/restic-backup.sh b2
```

## Verify

```bash
# When does the next run fire?
systemctl list-timers restic-backup-*

# Latest run log
journalctl -u restic-backup-usb -n 200
journalctl -u restic-backup-b2 -n 200

# Snapshots in each repo
sudo -E bash -c 'set -a; source /etc/restic.env; set +a; \
  RESTIC_REPOSITORY="$RESTIC_REPOSITORY_USB" restic snapshots'
```

## Restore a file (do this quarterly to confirm backups work)

```bash
sudo -E bash -c 'set -a; source /etc/restic.env; set +a; \
  RESTIC_REPOSITORY="$RESTIC_REPOSITORY_USB" \
  restic restore latest --target /tmp/restore-test --include /srv/caddy/Caddyfile'
diff /srv/caddy/Caddyfile /tmp/restore-test/srv/caddy/Caddyfile
```

## Restore a Postgres database

```bash
# 1. Restore the dump file
sudo -E bash -c 'set -a; source /etc/restic.env; set +a; \
  RESTIC_REPOSITORY="$RESTIC_REPOSITORY_USB" \
  restic restore latest --target /tmp/dbrestore --include /tmp/restic-dumps.*/immich.pgdump'

# 2. Reset the target database (be sure you actually want this)
cd /srv/immich
docker compose down database
sudo rm -rf /mnt/data/immich/postgres/*
docker compose up -d database
sleep 10

# 3. Restore the dump
docker exec -i immich_postgres pg_restore -U postgres -d immich --clean --if-exists \
  < /tmp/dbrestore/tmp/restic-dumps.*/immich.pgdump

# 4. Bring the rest of immich back up
docker compose up -d
```

## Lose the box entirely

The recovery path on new hardware varies by stage.

**[stage 1]** There is no restic recovery, because there are no restic snapshots. The recovery is reconstruction from upstream services per `README.md` "Recovery notes" -> stage 1 entry: re-sync from iCloud / Google Photos into a fresh Immich, re-clone the Obsidian vault from the laptop, re-rip Jellyfin media, accept loss of any homelab-only Matrix history. This is the explicit stage-1 risk acceptance from `docs/staged-rollout.md`.

**[stage 2]** B2-only recovery:

1. Reinstall Debian, run `bootstrap/debian-setup.sh`.
2. Reattach (or new-attach) the stage-2 data drive, LUKS-unlock it, mount at `/mnt/data` (procedure in `docs/encryption-at-rest.md`).
3. Pull credentials from your password manager to reach B2. `restic restore latest --target /` from the B2 repo. This puts `/srv`, `/mnt/data`, and the dumps back.
4. `cd /srv/<app> && docker compose up -d` for each app, in the same order as the original bootstrap.

**[stage 3]** Full recovery with both repos available:

1. Reinstall Debian, run `bootstrap/debian-setup.sh`.
2. Mount the existing USB backup drive (preferred, faster) or pull credentials from a password manager to reach B2.
3. `restic restore latest --target /` from the chosen repo. This puts `/srv`, `/mnt/data`, and the dumps back.
4. `mdadm --assemble --scan` to bring the HDD mirror back if you still have it; otherwise create a new mirror with `bootstrap/mdadm-mirror.sh` and let restic populate it.
5. `cd /srv/<app> && docker compose up -d` for each app, in the same order as the original bootstrap.
