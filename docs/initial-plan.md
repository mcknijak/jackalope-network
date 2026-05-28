# Homelab Server: Initial Plan

Drafted 2026-05-28.

## Goals

Self-host the following on a single home server:

1. Personal Obsidian docs sync (across desktop and mobile).
2. Video hosting (own a media library, stream to TV and phones).
3. Photo hosting and sharing (Google Photos replacement, with album sharing for a small group).
4. Encrypted chat for a small trusted group.

## Constraints set during planning

- Budget: $400 to $800 for all hardware.
- Access scope: me plus a few trusted people. No semi-public sharing yet, though the design should allow growing into it.
- Tech comfort: comfortable on the Linux CLI and with Docker Compose. Willing to learn reverse proxies and basic networking.
- Storage need in year one: 2 to 8 TB.
- Internet: Xfinity modem and router combo. Open to a second router or VLAN setup if there is a real reason.

## 1. Hardware recommendation (about $550 to $700 total)

### The box: two options

| Option | Approx cost | Pros | Cons |
|---|---|---|---|
| Refurb Dell OptiPlex 7060 or 7070 SFF (i5-8500, 16 GB, 256 GB NVMe) | $200 to $280 | One 3.5 inch and one 2.5 inch internal bay, so no external enclosure is required. Intel QuickSync for Jellyfin hardware transcoding. Easy RAM upgrade. | About 25 to 40 W idle. |
| New mini PC with Intel N100 (Beelink, Minisforum, etc., 16 GB, 500 GB) | $250 to $350 | About 10 W idle, silent, tiny footprint. Modern QuickSync. | No internal 3.5 inch bay, so a USB DAS is needed. Adds cost and a USB hop in the data path. |

**Pick:** the OptiPlex 7060 SFF. Single box, SATA drives instead of USB, cheaper overall, and the 8th-gen Intel i5 with QuickSync handles every app in scope. Buy refurbished on eBay or from Dell Refurbished.

### Storage

- Two 8 TB WD Red Plus (CMR) or Seagate IronWolf drives. About $160 each new, $100 each used. Mirror them with mdadm RAID1 or btrfs raid1 for 8 TB usable and one-drive failure tolerance.
- Keep the NVMe SSD for the operating system and app working data (databases, Docker volumes). The HDD mirror is for bulk media and photo originals.
- One 8 TB USB external drive (about $130) for local snapshot backups.

### RAM

16 GB is enough for everything below. Bump to 32 GB only if a VM or a heavy Matrix workload shows up later.

### Subtotal

OptiPlex $250 + two 8 TB drives $300 + USB backup drive $130 = about $680.

## 2. Networking: skip the second router for now

The "me plus a few trusted people" access pattern argues strongly for Tailscale instead of port forwarding.

- **Tailscale (free tier)** gives every device a private WireGuard tunnel into the home LAN. No ports opened on the Xfinity gateway. Works through CGNAT. End-to-end encrypted. Up to 100 devices and 3 users on the free plan.
- A separate router or VLAN setup is not needed at the start. Reasons to add one later: isolating IoT devices, running Pi-hole or AdGuard as the LAN DNS, exposing services to people who cannot install a VPN client. None of these are urgent.
- **For sharing a photo album with a non-technical relative:** use Tailscale Funnel or a Cloudflare Tunnel to publish a single subdomain over HTTPS, without opening ports on Xfinity. Cloudflare Tunnel is free and well-suited to this.

Xfinity gateway note: bridge mode on the Xfinity gateway disables WiFi and most admin features, which is why this plan avoids inbound NAT entirely. Tailscale and Cloudflare Tunnel sidestep the gateway, so bridge mode is not required.

## 3. Software stack

- **OS:** Debian 12 server, no GUI. Leaner than Ubuntu and very stable for this use case. Ubuntu Server 24.04 LTS is a fine alternative.
- **Containers:** Docker plus Docker Compose. One `compose.yml` per app stack, all living under `/srv/`.
- **Reverse proxy:** Caddy. Automatic HTTPS, very simple config. Use the DNS-01 challenge so certificates can be issued even without inbound ports open.
- **Remote access:** Tailscale.
- **Secrets:** per-stack `.env` files, kept out of git via `.gitignore`. At this scale this beats Vault or SOPS.
- **Backups:** restic, run on a systemd timer. Nightly to the external USB drive. Weekly to Backblaze B2 for the small, critical datasets.

### Apps

| Need | Pick | Why |
|---|---|---|
| Obsidian sync | CouchDB plus the Self-hosted LiveSync plugin | The de facto solution for Obsidian. Works on iOS, Android, and desktop with conflict resolution. Alternative: Syncthing if folder sync is enough and LiveSync features are not needed. |
| Video hosting | Jellyfin | Fully open source, no required account servers, hardware accelerated via QuickSync on the OptiPlex. |
| Photo hosting and sharing | Immich | Strong Google Photos style UI, mobile auto-backup, face recognition, album link sharing. Actively developed. |
| Encrypted chat | Matrix (Synapse) with Element clients | Self-hostable, federated if wanted, end-to-end encryption available per room. SimpleX is more private but the UX is rougher and weaker for a friend group. Signal cannot be self-hosted. |

## 4. Step-by-step plan

1. Buy hardware (OptiPlex, two 8 TB drives, 8 TB USB). About a week of lead time on eBay is typical.
2. Install Debian 12 to the NVMe. Enable SSH, disable root password login, add the SSH key.
3. Mirror the HDDs: `mdadm --create /dev/md0 --level=1 --raid-devices=2 /dev/sda /dev/sdb`, format ext4 or btrfs, mount at `/mnt/data`.
4. Install Docker and Compose from the official Docker repository (not the snap).
5. Install Tailscale, run `tailscale up`, note the `100.x.x.x` IP.
6. Buy a domain (about $12 per year at Porkbun or Cloudflare). Point a wildcard `*.home.yourdomain.com` record at the Tailscale IP via Cloudflare DNS.
7. Stand up Caddy as the reverse proxy with the DNS-01 cert challenge (Cloudflare provider). All apps live behind `*.home.yourdomain.com`.
8. Bring up apps one at a time, in this order so problems stay isolated: Immich, then Jellyfin, then CouchDB plus the Obsidian plugin, then Synapse plus Element.
9. Configure restic backups on a systemd timer: nightly to USB, weekly to B2.
10. Document the setup in this repo's README as it gets built.

## 5. Costs and upkeep

**Up front:** about $680 hardware plus $12 for a domain, so about **$692**.

**Recurring:**

- Power: OptiPlex SFF at about 30 W average is roughly 22 kWh per month, or about **$3 to $5 per month** depending on region.
- Backblaze B2: about $6 per TB per month. For 200 GB of critical data, about **$1.20 per month**.
- Domain: about **$1 per month** amortized.
- Tailscale, Caddy, and every app on the list are free.

**Total recurring: about $6 to $10 per month.**

**Upkeep effort:**

- 15 minutes per month: `apt upgrade`, pull updated container images, check disk health with `smartctl`, verify the last backup ran.
- Once a quarter: restore one file from backup to confirm it actually works. Backups that are never tested are not backups.
- Once a year: review what is actually being used and prune unused stacks.

## 6. Repo layout to scaffold

```
homelab-server/
├── README.md                # runbook: how to bootstrap, how to recover
├── .gitignore               # exclude *.env, secrets, data dirs
├── docs/
│   └── initial-plan.md      # this document
├── bootstrap/
│   ├── debian-setup.sh      # one-shot: packages, users, ssh, docker, tailscale
│   └── mdadm-mirror.sh      # creates and mounts /mnt/data
├── caddy/
│   ├── compose.yml
│   └── Caddyfile            # one site block per app, DNS-01 cert
├── immich/
│   ├── compose.yml
│   └── .env.example
├── jellyfin/
│   └── compose.yml
├── obsidian-couchdb/
│   ├── compose.yml
│   ├── .env.example
│   └── README.md            # LiveSync plugin config notes
├── matrix/
│   ├── compose.yml          # Synapse plus Postgres
│   ├── .env.example
│   └── homeserver.yaml.example
└── backups/
    ├── restic-backup.sh
    ├── restic-backup.service
    └── restic-backup.timer
```

## Open questions to settle before scaffolding the repo

1. Is a domain already registered? If not, the default assumption is Cloudflare-registered (cheap, free DNS API that Caddy can use).
2. Should Matrix federate with the wider Matrix network, or stay fully closed and private?
3. For photo sharing, is Immich's "share album via link" enough, or is there a need for true public web galleries that require no app at all?

Once those are answered, the next step is to generate the `bootstrap/` scripts, the per-app `compose.yml` files, the `Caddyfile`, and the restic systemd units in this repo so there is a working starting point to clone onto the box when it arrives.
