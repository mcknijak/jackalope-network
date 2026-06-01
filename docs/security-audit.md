# Security Audit

Audit date: 2026-05-28. Reviewer: in-house. Re-review after any major architecture change, and at least annually.

> **Stage scope:** the controls and gaps in this audit describe the stage-3 deployment (LUKS on the RAID1 mirror, restic to local USB nightly and Backblaze B2 weekly, full 3-2-1 backup, friends and family on the box). At stage 1 most of these controls are not yet in place; the stage-1 risk acceptance ("every data class is a mirror of a still-live upstream, the box holds no copy that is the only copy of itself") is what makes that acceptable. At stage 2 LUKS is on the data drive and B2 backups exist, but local USB backups and RAID1 redundancy do not. The audit posture below is the bar that has to be met before friends and family come on, which is also the trigger for advancing to stage 3. See `docs/staged-rollout.md`.

## Threat model

The scaffolding is hardened against threat model **(b): targeted but not nation-state**. Concretely, this means defending against:

- An attacker who knows you specifically and wants your data (chat logs, photos, notes), not just opportunistic scanners.
- Theft of the physical box or one of its drives.
- Theft of the external USB backup drive.
- Compromise of one upstream service (a single app exploit) without that giving the attacker the rest of the stack.
- Casual snooping on the LAN by household guests or by Xfinity itself.

Explicitly **out of scope**:

- Nation-state actors with physical seizure plus cold-boot RAM attacks.
- Compromise of Tailscale's coordination plane (treated as trusted infrastructure).
- Compromise of Porkbun, Backblaze B2, or Tailscale's edge / coordination plane (the latter is also called out separately in the open gaps section).
- Insider attacks by users you have already granted accounts to.

If the threat model ever shifts (for example, if any of the data becomes legally sensitive or you start hosting accounts for people who do not trust you), revisit this doc.

## What the data is, and how it is protected end to end

| Data | Where it lives | In transit | At rest on server | In backups | Notes |
|------|----------------|-----------|-------------------|------------|-------|
| Obsidian notes | CouchDB on the mirror | TLS via Caddy | LUKS on the mirror (see below) | restic AES-256 to USB and B2 | LiveSync plugin uses CouchDB password auth |
| Photos / videos (private) | Immich library on the mirror | TLS via Caddy | LUKS on the mirror | restic AES-256 to USB and B2 | Originals are the irreplaceable copy. B2 holds the offsite copy |
| Photos (shared via link) | Same Immich library | TLS via Tailscale Funnel (TCP passthrough) to Caddy | Same | Same | Anyone with the link can view, but only the album the owner specifies |
| Movies, shows, music | Jellyfin library | TLS via Caddy | LUKS on the mirror | Not backed up (re-acquirable) | Tailnet-only |
| Chat (Matrix) | Synapse Postgres + media store | TLS via Caddy | LUKS on the mirror | restic AES-256 to USB and B2 | E2EE rooms add a second encryption layer on top |
| Ebooks (Calibre-Web library) | `/mnt/data/ebooks` on the mirror | TLS via Caddy | LUKS on the mirror | restic AES-256 to USB and B2 | OPDS endpoint authenticated by Calibre-Web user/password |
| Audiobooks + podcasts (Audiobookshelf) | `/mnt/data/spokenword` on the mirror | TLS via Caddy | LUKS on the mirror | restic AES-256 to USB and B2 | Treated Obsidian-class; media files included in backups |
| Document archive (Paperless-ngx) | `/mnt/data/cabinet` on the mirror, plus Paperless Postgres | TLS via Caddy | LUKS on the mirror | restic AES-256 to USB and B2; Postgres logical dump alongside | Stage 2+ only. Most "would not want stolen-drive readable" data class in the stack; LUKS is the load-bearing protection. |
| Received receipt emails (Paperless mail rules) | Polled over IMAPS from `receipts@jackalope.network` at Porkbun, then deleted from server | IMAPS (TLS) | LUKS on the mirror once ingested as a Paperless document | restic AES-256 to USB and B2 | Whitelisted senders are consumed and deleted from the mailbox immediately. Non-whitelisted mail moves to a `Review` folder for human triage; manual move to `Approved` triggers ingestion, otherwise a weekly host-side cron purges `Review` after 30 days. Mailbox password lives in `/etc/cabinet-mailbox.env` (root-owned, 0600). |
| Portainer config | `/mnt/data/portainer/data` Docker volume | TLS via Caddy | LUKS on the mirror | restic AES-256 to USB and B2 | Tailnet-only access; never on Funnel. See "Portainer trust boundary" below. |
| Server config + secrets | `/srv` on the NVMe | n/a | OS disk is not LUKS-encrypted (see Open Gaps) | restic AES-256 | `.env` files contain DB passwords, API keys |
| restic backup archives | USB drive plus Backblaze B2 | TLS to B2 | restic native AES-256 (filesystem layer is plain ext4) | n/a | Single passphrase unlocks both repos |

## What the scaffold already gets right

These were in place before the audit:

- **All app traffic is TLS-terminated by Caddy**, with certs issued via Porkbun DNS-01 (no inbound 80/443 required). No app is reachable over plain HTTP.
- **No host ports are published for app containers.** Caddy is the only thing on the `proxy` Docker network with the outside world. Postgres, Redis, and Synapse itself listen only on internal Docker networks.
- **Tailscale-only by default.** Subdomain A records point to a `100.x.x.x` tailnet address. Anyone off the tailnet cannot reach DNS-resolved hosts. The exceptions are the welcome page root and `photos.jackalope.network`, both via Tailscale Funnel; Funnel does TCP passthrough so TLS still terminates at Caddy with our own Let's Encrypt cert.
- **SSH key-only, root login disabled, fail2ban active.** Set in `bootstrap/debian-setup.sh`.
- **UFW deny-by-default inbound**, allowing only `OpenSSH` and traffic on `tailscale0`.
- **Unattended security updates** for OS packages.
- **restic backups are encrypted at the restic layer** with a passphrase that is independent of any disk encryption. Even an attacker who exfiltrates the USB drive or the B2 bucket cannot read snapshots without the passphrase.
- **Postgres dumps run before each restic snapshot**, so backup snapshots are application-consistent and restorable to a different Postgres version.
- **Synapse federation is closed** (`federation_domain_whitelist: []`), shrinking the network attack surface and removing the federated-DM spam vector.

## Hardening added by this audit

These changes go in alongside this document. See cross-referenced files for the actual edits.

### LUKS on the data mirror

- `bootstrap/mdadm-mirror.sh` now prompts whether to add LUKS encryption to the mirror. If yes, the script runs `cryptsetup luksFormat` on the assembled `/dev/md0`, opens the resulting mapper, and lays ext4 on top.
- The OS NVMe stays unencrypted so the box can reboot unattended. Only `/mnt/data` requires a passphrase, which is entered manually over SSH after each reboot.
- Operating procedure for unlock is documented in `docs/encryption-at-rest.md`.
- A Dropbear-in-initramfs setup (full-disk encryption with remote unlock) is described in the same doc as an upgrade path if you ever want to also encrypt the OS disk.

### Matrix E2EE on by default

- `matrix/homeserver.yaml.example` now sets `encryption_enabled_by_default_for_room_type: all`. Every new room is end-to-end encrypted unless the creator explicitly turns it off, which they can still do per room (so bridges and bots that cannot handle E2EE remain usable).
- `matrix/README.md` gained a "Key backup setup" section. Every user has to enable Secure Backup in Element settings the first time they log in, or they will lose access to their own message history if they ever wipe a device or log out fully.

### Matrix hardening (rate limits, URL preview SSRF defense, registration tokens)

- `homeserver.yaml.example` adds `url_preview_ip_range_blacklist` covering RFC1918, link-local, loopback, and metadata-service addresses. Prevents the URL-preview fetcher from being used to scan the internal network or hit cloud metadata endpoints.
- `registration_requires_token: true` is set even though `enable_registration: false`. Belt and suspenders if registration is ever flipped on by accident.
- Login and message rate limits tightened slightly from defaults to slow credential stuffing.

### Portainer trust boundary

Portainer at `portainer.jackalope.network` (added 2026-06-01) talks to a local Portainer agent over the internal Docker network. The agent mounts `/var/run/docker.sock`, which is functionally equivalent to root on the host: any caller that can talk to the socket can launch privileged containers that mount the host filesystem.

This raises the consequences of a Portainer admin credential leak from "someone can manage some containers" to "someone has root on the box." Mitigations:

- **Tailnet-only, never on Funnel.** The Caddy site block has no public ingress. Adding Funnel to Portainer is an out-of-policy change; the documented escape valve when remote container management is needed is SSH plus `docker compose`, not Funnel.
- **Admin credential lives only in the password manager.** Same posture as the LUKS and restic passphrases. No second-factor in the initial scaffold; worth enabling under User Settings once Portainer becomes a frequent-use UI.
- **No additional user accounts unless absolutely necessary.** The threat model does not include "household members who need partial Docker access." If a friend ever needs to see one container's logs, screen-share an SSH session; do not issue a Portainer login.
- **Not advertised on the welcome page.** Portainer is deliberately omitted from `welcome/src/data/tiles.js` so the public landing page does not surface its existence to visitors. The hostname `portainer.jackalope.network` resolves on the tailnet, but discovery requires already knowing it's there.
- **Agent architecture from day one.** The Portainer container itself does not mount the socket; only the agent does. This makes adding a second host (a Pi for off-site backups, a second SFF) trivial: the new host runs only the agent and is added as an environment in the UI. Same security boundary, no architectural rework.

The reason this is called out separately rather than rolled into the "what was deliberately not hardened" list: Portainer's blast radius is materially larger than any other app in the stack. Immich admin compromise loses photos; Portainer admin compromise loses the box.

### Cabinet (Paperless-ngx) IMAP credential surface

Cabinet polls `receipts@jackalope.network` over IMAPS. The mailbox password is stored in two places: Paperless's encrypted secret store (managed by the Paperless container, keyed off `PAPERLESS_SECRET_KEY` from `cabinet/.env`), and `/etc/cabinet-mailbox.env` (root-owned, 0600) used by the weekly Trash-purge cron. Both `cabinet/.env` and `/etc/cabinet-mailbox.env` are inside the OS-disk plaintext envelope (see Open Gaps). The mailbox is a single-purpose receive-only inbox at Porkbun, so the worst-case impact of credential leak is read access to whatever receipts haven't been purged yet plus the ability to inject documents into Paperless's consume queue. Mitigation if leaked: rotate the mailbox password at Porkbun in under a minute, update both files, restart `paperless` and the cron unit.

### Backup repo separation

No change to scaffolding, but a clarification worth recording: the restic passphrase is the only thing that protects offsite backups. It is **not** the LUKS passphrase, and it is **not** any account password. Store it in a password manager that is itself backed up somewhere independent (printed paper in a safe, separate device, etc.). Without the passphrase, the B2 bucket is a brick.

## What was deliberately not hardened, and why

These were considered and skipped. Recording the reasoning so future-me does not relitigate them without cause.

- **Full-disk encryption on the OS NVMe.** Would protect `/etc`, `/srv` (env files, secrets, Caddyfile), and journal logs at rest. Cost: every reboot needs an interactive unlock before SSH comes up, which means the box cannot recover unattended from a power blip. The Dropbear-over-Tailscale workaround works but adds initramfs surgery and a second SSH key path to maintain. For threat model (b), LUKS on the data mirror plus restic-encrypted backups covers the actual sensitive data. The NVMe gap is acceptable.
- **Two-factor on SSH.** SSH is already key-only with PasswordAuthentication off, and the SSH port is only reachable from the tailnet. Adding TOTP would mean approving every login from a phone, which is operationally painful for a server you SSH into multiple times a week. The actual chokepoint is the SSH private key file plus the Tailscale device key, both already protected at the device level.
- **Hardware security key for SSH.** Same reasoning. Worth revisiting if the SSH key ever leaves a controlled device.
- **Per-app egress firewalling.** Containers can talk to the public internet freely. A targeted egress policy (e.g., Immich is only allowed to reach update servers) would limit damage from a single-app RCE. Cost is high (per-app allowlists need maintenance every time an upstream URL changes). Skipped as not worth the operational tax for a homelab.
- **Image signing / supply chain verification.** Pulling `immich:latest` trusts the upstream registry. Sigstore/cosign verification is possible but most homelab images do not sign, and the failure mode (a malicious upstream image) is rare enough relative to the operational cost. Mitigation: pin to release tags (not `latest`) for anything you actually care about, and read release notes before pulling. Documented as deferred in `docs/scaffolding-summary.md`.
- **Intrusion detection (Wazuh, etc.).** A homelab does not generate enough log signal to justify a full SIEM. fail2ban on SSH covers the realistic case. Revisit if you start hosting accounts for people outside the trusted few.
- **DNS over HTTPS / encrypted client hello.** The DNS path is already only inside the tailnet plus the Porkbun API call from Caddy. Adding DoH everywhere would not change what an on-LAN attacker sees.
- **Tailscale ACLs locking down which devices can reach which services.** Would let, for example, your phone reach Immich but not SSH. Worth doing once the device list grows past two or three. Current device count is small enough that the operational cost outweighs the benefit. Re-evaluate when the tailnet has 5+ devices or you add a household member.

## Open gaps (accepted, but worth knowing)

- **OS disk is plaintext.** Stolen NVMe yields config and the encrypted-at-rest restic passphrase only if it is cached anywhere (it should not be: load `/etc/restic.env` on demand, do not store in shell history). It also yields any `.env` file (DB passwords, Porkbun API keys, B2 keys). Compensating control: those credentials can be rotated quickly if you ever lose physical control of the box.
- **Xfinity gateway is a black box.** It sees DNS queries from the LAN and any plaintext metadata. Mitigation: the actual data traffic leaves the LAN over WireGuard (Tailscale) or as TLS, and Funnel is also outbound-only WireGuard from the server's perspective. If you want to close the DNS gap, point the box's resolver at a DoH provider in `/etc/systemd/resolved.conf`.
- **Tailscale is a single point of trust.** If Tailscale's coordination service is compromised, an attacker could potentially add a device to your tailnet. Mitigation: enable tailnet lock (tailscale lock) once you have at least two long-lived signing devices set up. Not done in the initial scaffold because tailnet lock setup is non-trivial and the threat is low. Documented as a future hardening step.
- **Backups encrypted with a single passphrase.** If the passphrase leaks, both copies of the data are at risk. Mitigations already in place: passphrase is long, stored in a password manager, never transmitted. Mitigation to consider: keep a separate restic repo with a different passphrase for the most sensitive subset (e.g., Matrix media). Skipped for v1.

## Verification routine

Run these quarterly, or after any significant change:

1. `nmap -p- <public IP>` from off-network. Expect zero open ports. Tailscale Funnel routes public traffic through Tailscale's edge, so the home IP should never appear in DNS for any jackalope.network host.
2. `nmap -p- <tailnet IP>` from a tailnet device. Expect 22 (SSH), 443 (Caddy), 80 (Caddy redirect).
3. `docker network inspect proxy` and confirm only Caddy plus the per-app frontends are attached. Postgres / Redis containers should not appear.
4. Test a restic restore of one file from the USB repo and one file from the B2 repo.
5. Confirm LUKS unlock procedure still works: reboot the server, then SSH in and complete the unlock procedure from `docs/encryption-at-rest.md`. If the procedure has drifted from the doc, fix the doc.
6. Confirm Element shows the green "Secure Backup is on" indicator for every active user account.
7. Verify Synapse version is current: `docker compose exec synapse python -m synapse.app.homeserver --version` against the upstream release page.
8. Confirm unattended-upgrades has run recently: `journalctl -u unattended-upgrades --since '1 week ago'`.

## Incident-response notes

If you suspect compromise:

1. **Disconnect.** `tailscale down` on the server. This severs all live sessions including yours, so do it from a local console if possible.
2. **Snapshot for forensics before changing anything.** `dd` the NVMe to an external drive if you can; at minimum copy `/var/log`, `/etc`, all `.env` files, and recent restic snapshot IDs.
3. **Rotate every credential.** Porkbun API keys, B2 keys, all `.env` passwords, Matrix admin account, Tailscale device key (force re-auth from the admin console). The LUKS passphrase only matters if the box was physically removed.
4. **Decide whether to rebuild from a known-good snapshot.** Pick a restic snapshot from before the suspected compromise window, restore to fresh hardware (or wiped same hardware), and bring up from scratch.
5. **Document what happened** in this audit file under a new dated section so the next review can check that the relevant gap was closed.
