# Matrix (Synapse + Element)

Private Matrix homeserver for `jackalope.network`. Federation is off (see `docs/decisions.md`). Element Web is included as the default client at `https://element.jackalope.network`.

> **Stage scope:** the setup below writes data to `/mnt/data/matrix/`, which at stage 3 is the LUKS-encrypted RAID1 mirror. At stages 1 and 2, `/mnt/data` is either plain directories on the OS disk (stage 1) or a single LUKS-encrypted drive (stage 2). The path stays the same in either case; only the underlying storage shape changes. Make sure the per-app directories exist (`bootstrap/debian-setup.sh` echoes the `mkdir` command, or `bootstrap/mdadm-mirror.sh` creates them at stage 3) before running the steps below. The E2EE-on-by-default plus Secure Backup user setup applies identically at every stage.

## First-time setup

1. **Set the Postgres password.** Copy `.env.example` to `.env` and set `POSTGRES_PASSWORD` (use `openssl rand -hex 24`).

2. **Generate Synapse's initial config.** This writes `homeserver.yaml`, signing keys, and the log config to `/mnt/data/matrix/synapse`.

   ```bash
   docker compose run --rm \
     -e SYNAPSE_SERVER_NAME=jackalope.network \
     -e SYNAPSE_REPORT_STATS=no \
     synapse generate
   ```

3. **Edit the generated `homeserver.yaml`.** Open `/mnt/data/matrix/synapse/homeserver.yaml` and bring it in line with `homeserver.yaml.example` in this directory. The fields that matter:

   - `database`: switch from the default SQLite block to the Postgres block from the example (and paste in the `POSTGRES_PASSWORD` from `.env`)
   - `listeners`: make sure the HTTP listener has `x_forwarded: true` so Synapse trusts the `X-Forwarded-For` header from Caddy
   - `federation_domain_whitelist: []` to keep federation off
   - `enable_registration: false`

4. **Start the stack.**

   ```bash
   docker compose up -d
   ```

5. **Create your first user.** Registration is closed, so users are made by hand:

   ```bash
   docker compose exec synapse register_new_matrix_user \
     -u jack \
     -a \
     -c /data/homeserver.yaml \
     http://localhost:8008
   ```

   The `-a` flag makes the user a server admin. Drop it for regular accounts.

6. **Log in via Element Web** at `https://element.jackalope.network`. It is preconfigured to talk to `https://matrix.jackalope.network`.

## Key backup: every user must do this on first login

Rooms in this deployment are end-to-end encrypted by default
(`encryption_enabled_by_default_for_room_type: all`). E2EE means the
server stores ciphertext only. If a user loses their device keys
without a backup, they permanently lose access to their own message
history. This is a feature, not a bug, but it has a setup tax.

The fix is Element's Secure Backup. Every user, on first login, has to
do the following once per account:

1. Open Element Web, log in, accept the verification prompt.
2. Go to **Settings -> Security & Privacy -> Secure Backup -> Set up**.
3. Choose **Generate a Security Key** (you can also use a passphrase;
   the key is simpler).
4. Save the 48-character security key in your password manager. Treat
   it like the LUKS passphrase: lose it and the data is gone.
5. Confirm the green "Secure Backup is on" indicator appears in
   Settings -> Security & Privacy.

After this, signing into Element from a new device just requires
pasting the security key once to recover the message history.

If a user joins a room created by someone else, they have to be
verified by an already-trusted device for E2EE to bootstrap. Element's
emoji-verification flow handles this.

If a user wants a room to NOT be encrypted (for example, to bridge it
to Discord or to add a bot that does not handle E2EE), they can toggle
encryption off in the room-creation dialog. Once a room is encrypted,
it cannot be downgraded.

## Day-to-day

### Add a user

```bash
cd /srv/matrix
docker compose exec synapse register_new_matrix_user \
  -u alice -c /data/homeserver.yaml http://localhost:8008
```

### Reset a password

```bash
docker compose exec synapse hash_password
# paste the resulting hash into Postgres:
docker compose exec postgres psql -U synapse -d synapse \
  -c "UPDATE users SET password_hash = '<hash>' WHERE name = '@alice:jackalope.network';"
```

### Pull updates

```bash
docker compose pull && docker compose up -d
```

Synapse releases are roughly weekly. The major releases occasionally need a manual database migration; check the upstream release notes if `synapse` fails to start after a pull.

## Future: enabling federation

If you later decide to federate (see `docs/decisions.md` for trade-offs), the steps are:

1. Expose Synapse on the public internet for federation. Two reasonable paths: Tailscale Funnel (preferred; same daemon already handling the welcome page and photo sharing, keeps the rest of the stack closed, no second service to manage) or Cloudflare Tunnel as a fallback if Funnel bandwidth limits become a problem. Opening port 443 on the gateway directly is the third option but defeats the purpose of the rest of this design.
2. Set up federation delegation. Either run Synapse on the apex `https://jackalope.network/.well-known/matrix/server` returning `{"m.server": "matrix.jackalope.network:443"}`, or add an SRV record.
3. In `homeserver.yaml`, remove or empty `federation_domain_whitelist`.
4. Restart Synapse.

Rooms that were created while federation was off and that had `m.federate: false` set will not federate, ever. The Element client defaults to `default_federate: true` (see `element-config.json`), so rooms created from the web client will be eligible to federate once the server is opened up.
