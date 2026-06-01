# Encryption at Rest

Where data is encrypted on disk, what is not, and the operating procedure for the parts that need manual intervention.

> **Stage scope:** this doc describes the stage-3 end state (LUKS2 on the `/mnt/data` RAID1 mirror). At stage 1 there is no LUKS at all: data lives plaintext on the OS disk, which is acceptable only because every data class on the box is a mirror of a still-live upstream. The risk acceptance is spelled out in `docs/staged-rollout.md`. At stage 2, LUKS lives on the single stage-2 drive (internal or external) with the same passphrase model and post-reboot procedure described below, substituting the stage-2 device for `/dev/md0`. The OS-disk gap reasoning applies identically at stages 2 and 3. See `docs/staged-rollout.md` for the full lifecycle.

## What this covers

| Layer | Encrypted? | Key material | Notes |
|-------|-----------|--------------|-------|
| OS NVMe (`/`, `/etc`, `/srv`) | **No** | n/a | Plaintext. See "OS disk gap" below for the rationale and an optional upgrade path |
| Data mirror (`/mnt/data`) | **Yes**, LUKS2 with Argon2id | LUKS passphrase, manual unlock | Set up by `bootstrap/mdadm-mirror.sh` when you answer "y" to the LUKS prompt |
| USB backup drive (`/mnt/backup`) | Filesystem is plain ext4 | n/a | restic itself encrypts every snapshot before writing, so the underlying filesystem does not need to be encrypted |
| Backblaze B2 bucket | restic AES-256 | restic passphrase | Same restic passphrase as the USB repo |
| Matrix message bodies in encrypted rooms | E2EE (Megolm) | Per-device keys, backed up via Element Secure Backup | Server stores ciphertext only. See `matrix/README.md` for the user-side setup |
| Immich uploads in flight | TLS via Caddy (tailnet) or via Tailscale Funnel passthrough to Caddy (public photo shares) | Caddy-issued Let's Encrypt cert in both cases | At rest on the server they sit inside the LUKS-encrypted `/mnt/data` |
| CouchDB documents | No application-layer encryption | n/a | Protected at rest only by the underlying LUKS-encrypted `/mnt/data` |
| Ebook library (Calibre-Web) | No application-layer encryption | n/a | LUKS on `/mnt/data` at stages 2 and 3. Plaintext on the OS disk at stage 1 (the canonical library lives on the laptop / source store). |
| Audiobooks and podcasts (Audiobookshelf) | No application-layer encryption | n/a | Same as ebooks. LUKS on `/mnt/data` at stages 2 and 3; plaintext at stage 1. |
| Paperless OCR'd documents and Postgres | No application-layer encryption | n/a | Stage 2 and stage 3 only; LUKS on `/mnt/data` is the protection layer. This is the most "you would not want this read off a stolen drive" data class in the stack, which is the load-bearing reason cabinet is held back until LUKS exists. |
| Portainer config DB (admin user, env definitions) | No application-layer encryption | n/a | LUKS on `/mnt/data` at stages 2 and 3. Sensitivity is moderate (knowing the env layout is useful to an attacker but not directly exploitable); the Docker socket on the host is the actual high-value target, not Portainer's DB. |

## Why the OS disk is not encrypted

LUKS on the boot disk gives real protection but turns every reboot into a manual ceremony. Two paths exist:

1. Enter the passphrase at the physical console every time. Requires a monitor and keyboard plugged in, or IPMI / KVM-over-IP that the OptiPlex does not have.
2. Use Dropbear SSH in the initramfs so you can SSH in over the network and type the passphrase remotely. Works, but adds an initramfs that has to be maintained and a second SSH key path. Failed kernel updates can leave the box unbootable.

For the threat model in `docs/security-audit.md` (targeted but not nation-state), the calculus is:

- An attacker who steals the box has the OS disk. The OS disk contains: the Caddyfile, `.env` files with DB passwords and Porkbun / B2 API keys, journal logs that may reference DB rows, and the SSH `authorized_keys` for the operator account.
- It does **not** contain any user-generated content. Photos, notes, chat history, and media all live on `/mnt/data`, which is LUKS-encrypted and requires a separate passphrase that the OS disk does not hold.
- Compensating control: every credential exposed via the OS disk is rotatable in minutes (Porkbun API keys, B2 keys, all DB passwords, your Tailscale device key).

Net: the OS-disk gap costs you "I need to rotate a handful of secrets" if the box is stolen. The data itself stays sealed. That trade is acceptable for this threat model. If your threat model ever shifts, switch to the Dropbear-over-Tailscale upgrade path described at the bottom of this doc.

## Post-reboot procedure (LUKS-enabled `/mnt/data`)

Every reboot of the server requires this short sequence. Without it, `/mnt/data` is not mounted, so every app container will fail health checks and either restart-loop or exit. Caddy itself will come up (it lives on `/`, which is not encrypted) but every reverse-proxied app will be a 502.

> **Stage note:** the device path differs by stage. **Stage 3** uses `/dev/md0` (the mdadm mirror). **Stage 2** uses the single stage-2 drive directly: typically `/dev/sdb` (or whatever `lsblk` shows for your data drive). **Stage 1** has no LUKS, so this whole procedure does not apply; reboot is unattended. Substitute the right device in step 2 below.

1. SSH to the box from a tailnet device:

   ```bash
   ssh jack@<tailnet-ip>
   ```

2. Unlock the LUKS container. You will be prompted for the passphrase you set during `bootstrap/mdadm-mirror.sh` (stage 3) or during your stage-2 `cryptsetup luksFormat`:

   ```bash
   # stage 3 (RAID1 mirror):
   sudo cryptsetup open /dev/md0 data-crypt

   # stage 2 (single drive, substitute your device):
   sudo cryptsetup open /dev/sdb data-crypt
   ```

3. Mount it:

   ```bash
   sudo mount /mnt/data
   ```

4. Restart every Docker Compose stack. The cleanest way is to bring up every stack under `/srv` in order:

   ```bash
   for d in /srv/caddy /srv/immich /srv/jellyfin /srv/obsidian-couchdb /srv/matrix; do
     (cd "$d" && docker compose up -d)
   done
   ```

   Caddy first, then the apps. If `caddy` was already running (it should be, since it does not depend on `/mnt/data`), bringing it "up" is a no-op.

5. Confirm everything is healthy:

   ```bash
   docker ps
   curl -sI https://immich.jackalope.network | head -1
   ```

If you forget step 2 or 3, you will notice quickly: every app subdomain returns 502 from Caddy. The fix is just to unlock and mount as above; no data is at risk.

### Locking again (rare)

If you ever want to actively re-lock without rebooting (paranoia, planned physical move, etc.):

```bash
for d in /srv/*/; do (cd "$d" && docker compose down); done
sudo umount /mnt/data
sudo cryptsetup close data-crypt
```

A reboot does the same thing more thoroughly.

## Passphrase management

- The LUKS passphrase is **only** in your password manager. Do not store it anywhere on the box.
- The restic passphrase is a **different** value, also only in your password manager. If they are ever the same, fix it: a single compromise should not unlock both encryption layers.
- Both should be long (24+ characters, randomly generated by the password manager). Argon2id makes brute force expensive but does not save you from a weak passphrase.
- Keep a printed copy of both passphrases in a physical safe. If your password manager is ever lost together with the device that has it cached, the printed copy is your last resort.

## Rotating the LUKS passphrase

LUKS supports multiple key slots. To rotate without downtime:

```bash
# 1. Add the new passphrase as an additional slot (you will be prompted
#    for an existing passphrase to authorize, then the new one twice).
sudo cryptsetup luksAddKey /dev/md0

# 2. Verify the new passphrase actually unlocks (after a test reboot,
#    or by closing and reopening the container with the new passphrase).

# 3. Remove the old passphrase only after the new one is confirmed.
sudo cryptsetup luksRemoveKey /dev/md0
# (you will be prompted for the passphrase to remove)
```

## Upgrade path: full-disk encryption with Dropbear-over-Tailscale unlock

This is documented but not part of the initial scaffolding. Pursue if your threat model shifts to "the OS disk itself is sensitive" (for example, you start hosting accounts for people who do not trust you, or you store legal-discovery-relevant data in plaintext config).

Outline of what changes:

1. Reinstall Debian onto LUKS at install time (the Debian installer has a "guided, encrypted LVM" option).
2. Install Dropbear and the relevant initramfs hooks:
   ```bash
   sudo apt install dropbear-initramfs
   ```
3. Configure Dropbear to come up with a static IP that Tailscale-side scripting can reach, or set up a second NIC just for the unlock path. Tailscale itself cannot run in the initramfs, so you typically expose Dropbear on the LAN and rely on a VPN endpoint or a trusted home network for the unlock window.
4. Copy your operator SSH public key into `/etc/dropbear-initramfs/authorized_keys`.
5. Update the initramfs: `sudo update-initramfs -u`.
6. Reboot. The box will pause at an initramfs prompt; SSH in on the Dropbear port, run `cryptroot-unlock`, type the passphrase, and the boot continues.

Maintenance cost: every kernel update regenerates the initramfs. Watch for `dropbear-initramfs` package updates and test reboots on a known-good schedule.

If you go this route, also turn LUKS on the data mirror into auto-unlock from a keyfile on the (now-encrypted) root, so you do not need two passphrases per reboot. Update this doc when you do.
