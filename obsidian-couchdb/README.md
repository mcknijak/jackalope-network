# Obsidian sync via CouchDB

Self-hosted backend for the Obsidian [Self-hosted LiveSync](https://github.com/vrtmrz/obsidian-livesync) plugin.

## First-time setup

1. Copy `.env.example` to `.env` and set `COUCHDB_USER` and `COUCHDB_PASSWORD`. Pick a strong password (`openssl rand -hex 24`).
2. Bring up the stack: `docker compose up -d`.
3. Wait about 10 seconds for CouchDB to finish its first-run initialization, then run `./configure-cors.sh`. This enables CORS for the Obsidian client and tightens authentication.
4. Create the database the plugin will write to:
   ```
   curl -X PUT https://couchdb.jackalope.network/obsidian \
     -u obsidian:<password>
   ```
5. Confirm the database exists:
   ```
   curl https://couchdb.jackalope.network/_all_dbs -u obsidian:<password>
   ```

## Configure the Obsidian plugin

In every Obsidian client (desktop, mobile), install the Self-hosted LiveSync plugin from Community Plugins, then in its settings:

- URI: `https://couchdb.jackalope.network`
- Username: `obsidian` (or whatever you set)
- Password: the value from `.env`
- Database name: `obsidian`

On the first device, initialize the remote database from the plugin's "Remote Database configuration" tab. On every other device, do "Fetch from the remote database" instead so it pulls down, rather than uploading.

## Notes

- The CouchDB admin user (set via `COUCHDB_USER`) is the only user that can write to the database. You can create separate, lower-privileged users in CouchDB if multiple people share the vault, but for personal use one admin is fine.
- Backups: CouchDB stores data under `/mnt/data/couchdb/data`, which is picked up by the nightly restic run. To restore, drop the contents back into that directory before CouchDB starts.
- The vault itself is still local-first; CouchDB is only a sync target. If CouchDB is down, the Obsidian client keeps working and re-syncs when it comes back.
