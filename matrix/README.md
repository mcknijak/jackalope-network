# Matrix (Synapse + Element)

Private Matrix homeserver for `jackalope.network`. Federation is off (see `docs/decisions.md`). Element Web is included as the default client at `https://element.jackalope.network`.

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

1. Expose Synapse on the public internet for federation. Two reasonable paths: Cloudflare Tunnel (preferred, keeps the rest of the stack closed) or open port 443 on the gateway directly.
2. Set up federation delegation. Either run Synapse on the apex `https://jackalope.network/.well-known/matrix/server` returning `{"m.server": "matrix.jackalope.network:443"}`, or add an SRV record.
3. In `homeserver.yaml`, remove or empty `federation_domain_whitelist`.
4. Restart Synapse.

Rooms that were created while federation was off and that had `m.federate: false` set will not federate, ever. The Element client defaults to `default_federate: true` (see `element-config.json`), so rooms created from the web client will be eligible to federate once the server is opened up.
