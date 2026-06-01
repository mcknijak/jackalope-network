# portainer (Portainer CE + local agent)

Web UI for managing Docker containers, networks, volumes, and images across one or more hosts. Reached at `portainer.jackalope.network` on the tailnet.

> **Stage scope:** runs at every stage. State (the Portainer config DB) lives at `/mnt/data/portainer/data` and is backed up at stages 2 (B2 weekly) and 3 (USB nightly + B2 weekly). At stage 1 there is no backup, but Portainer is reconstructable in about ten minutes: re-deploy the compose file, set a new admin password, done. The live container / volume / network state Portainer manages is unchanged by a Portainer wipe because Portainer doesn't store any of it; that lives in Docker itself.

## Trust boundary

**Portainer plus its agent equals full root on the box.** The agent mounts the Docker socket, which is functionally equivalent to root: any caller who can talk to the socket can run privileged containers that mount the host filesystem.

This drives three rules:

1. **Tailnet-only. Never on Funnel.** The Caddy site block for `portainer.jackalope.network` has no public ingress and no Funnel CNAME. If you ever find yourself wanting public access to Portainer, the answer is "no, SSH and run `docker compose` by hand," not "open Funnel."
2. **Strong admin password, stored only in your password manager.** Same posture as the LUKS and restic passphrases. Reset via `docker exec -it portainer rm /data/portainer.db && docker restart portainer` if you ever lose it (this wipes Portainer's config DB and triggers the first-run wizard again; managed containers and volumes are untouched because they live in Docker, not in Portainer).
3. **No additional user accounts unless absolutely necessary.** Portainer supports multi-user with RBAC, but the threat model in `docs/security-audit.md` does not include "household members who need partial Docker access." If a friend ever needs to see a single container's logs, screen-share an SSH session; don't issue them a Portainer login.

## First-time setup

1. Bring up the stack:

   ```bash
   cd /srv/portainer && docker compose up -d
   ```

2. Open `https://portainer.jackalope.network` from a tailnet device, within five minutes of starting the container. (Portainer's first-run wizard times out after five minutes for security; if you miss the window, restart with `docker compose restart portainer`.)

3. Create the admin account. Username `admin`, password from your password manager.

4. On the "Environments" page, you should already see one environment: the local agent at `portainer-agent:9001`. If for some reason it's not there, add it manually as a Docker-Standalone-Agent environment, URL `portainer-agent:9001`.

5. Done. Containers, volumes, networks, images, and stacks across the local box are visible in the UI.

## Adding a second host later

When a second box joins (a Pi for off-site backups, a second SFF, etc.), the pattern is:

1. On the new host, install Docker and run **only** the Portainer agent (not Portainer itself):

   ```bash
   docker run -d -p 9001:9001 --name portainer-agent --restart unless-stopped \
     -v /var/run/docker.sock:/var/run/docker.sock \
     -v /var/lib/docker/volumes:/var/lib/docker/volumes \
     portainer/agent:latest
   ```

2. Make sure both hosts are on the same tailnet.

3. In the Portainer UI on the existing box, Environments -> Add environment -> Docker Standalone -> Agent. URL: `<new-host-tailnet-ip>:9001`. Give it a friendly name.

4. The new host appears in the environment dropdown. Same UI, two hosts.

The reason the stack here uses the agent locally (instead of mounting the socket directly into Portainer) is so this expansion is a non-event: the local Portainer doesn't change at all when a second host shows up.

## Things to know

- **No `:latest` pinning.** Both images use `:latest`. Portainer ships frequently and the CE upgrade path is reliably smooth, so `docker compose pull && docker compose up -d` once a month is the maintenance routine.
- **Two-factor authentication** is available under User Settings. Worth enabling once Portainer becomes a frequent-use UI; not enabled in the scaffolding because the tailnet-only access plus strong password already covers most of the threat.
- **Edge compute / EE features** like Edge Compute are not used. CE is sufficient for a homelab.
- **Backups.** Portainer's state directory is bind-mounted at `/mnt/data/portainer/data`, so restic picks it up directly at stage 2+ via the standard `/mnt/data` capture. The contents (admin users, env definitions, custom templates) restore cleanly. Managed Docker resources are not "in" Portainer's backup at all because Portainer doesn't own them; they live in Docker itself.
