# Staged Rollout

A phased lifecycle for standing this homelab up gradually, so the up-front cost is small enough that "I tried it for a few months and decided it wasn't for me" is a cheap outcome.

The end state in the rest of the docs (`README.md`, `security-audit.md`, `encryption-at-rest.md`, etc.) describes stage 3. Stages 1 and 2 are deliberately scoped-down versions of the same architecture, not a different design. Nothing has to be unlearned or thrown away when advancing a stage.

## The three stages at a glance

| Stage | Hardware | Storage posture | Backups | Encryption | Who uses it | Approximate spend |
|-------|----------|-----------------|---------|------------|-------------|-------------------|
| 1 | Used SFF office PC | Internal disk only | None on-box. All data is reconstructable from upstream services. | None | Just you, evaluating | ~$150 to $250 one-time |
| 2 | + one external (or second internal) drive | Photos and media on the external drive, notes and chat on internal | Backblaze B2 weekly via restic | LUKS2 on the external drive (manual unlock at attach) | Just you, committed | + ~$100 to $150 drive, + ~$2 to $4 per month B2 |
| 3 | + two server-grade NAS drives in mdadm RAID1 | All app data on the encrypted mirror, OS untouched | restic to USB nightly + B2 weekly (3-2-1) | LUKS2 with Argon2id on the mirror | You plus friends and family | + ~$200 to $300 for the two NAS drives |

The dollar figures are rough order of magnitude. Used PC prices in particular drift; verify on the day.

## Stage 1: PC only

**Goal:** prove to yourself you actually want this, before spending real money on drives, backup services, or sharing it with anyone else.

### Hardware

One used small-form-factor (SFF) office PC. SFF specifically (not the tiny / micro-form-factor variant, not a full tower) because:

- **Tiny / MFF** chassis (Dell Micro, ThinkCentre Tiny, HP Mini): only fit one 2.5" SATA drive plus an M.2 NVMe. That works fine at stage 1 but forces every stage-2 and stage-3 drive to live in external USB enclosures, which is a real reliability and noise downgrade.
- **SFF** chassis: has room for one 3.5" drive plus one or two 2.5" plus an M.2. This is what you want, because stage 3's NAS drives are 3.5" and belong inside the chassis.
- **Full tower:** more expansion than needed, more electricity, more noise. Overkill.

What to look for, in priority order:

1. **CPU with Intel Quick Sync** (8th-gen Core or newer, so i5-8500, i5-9500, i5-10500, i7-equivalents). Quick Sync gives Jellyfin hardware-accelerated transcoding without a discrete GPU. Critical if you ever play media on a device that needs transcoding (anything not direct-playing the source file).
2. **16 GB RAM**, or 8 GB with two free slots so you can add more cheaply later. The seven stage-1 apps plus Postgres can comfortably live in 16 GB. 8 GB works but you'll feel it once Immich's machine-learning workers run; the lighter-weight stage-1 additions (Calibre-Web, Audiobookshelf, Portainer) each consume under 500 MB at idle, so they don't move the needle much, but Postgres count goes up at stage 2 when Paperless adds a third instance.
3. **One M.2 NVMe slot** with a 256 GB or larger drive already installed (this is the OS disk). Most SFFs ship this way.
4. **One free 3.5" bay** plus the SATA cables and a power lead. Sometimes the bay is there but the cable isn't; that's usually a $10 fix.
5. **Gigabit Ethernet.** Standard on anything from this era.

Models that consistently hit the sweet spot on the used market:

- **Dell OptiPlex 7060 / 7070 / 7080 / 7090 SFF** (7060 is 8th gen, 7090 is 10th)
- **HP EliteDesk 800 G4 / G5 / G6 SFF**
- **Lenovo ThinkCentre M720s / M920s SFF**

Any of these in the i5 + 16 GB + 256 GB NVMe config typically goes for $150 to $250 on eBay or from refurbishers like PCLiquidations or Discount Electronics. Avoid anything pre-8th-gen, you lose Quick Sync's modern codec support.

What is *not* needed at stage 1: discrete GPU, ECC RAM, redundant power supply, IPMI / iDRAC. The OptiPlex / EliteDesk / ThinkCentre lines don't have any of these and that's correct.

### What runs

At stage 1, the following apps come up from day one: Immich, Jellyfin, Obsidian LiveSync (CouchDB), Matrix/Synapse plus Element Web, Calibre-Web (ebooks), Audiobookshelf (audiobooks plus podcasts), and Portainer (container management UI). Caddy out front. Tailscale plus Funnel exactly as described in the main README. The welcome page served from `/srv/welcome/dist`.

Paperless-ngx (cabinet) is the one app explicitly held back until stage 2. Its value proposition is "I trust this archive enough to shred the original," which requires the backup story stage 2 introduces. Adding it at stage 1 would invite you to feed it irreplaceable documents that the box is not yet equipped to protect.

The only difference from stage 3 is that everything writes to the single factory-installed HDD (or NVMe, if the box came with NVMe only, in which case stage 1 is squeezed into whatever capacity that drive has).

**Storage paths at stage 1.** The per-app compose files reference `/mnt/data/<app>/` paths because that's the stage-3 mount. At stage 1 there is no `/mnt/data` mount, but the path still works fine: just create the directories on the OS disk first and the compose volume mounts resolve to plain directories on the NVMe. No compose-file edits needed.

```bash
sudo mkdir -p /mnt/data/{immich/library,immich/postgres,\
  jellyfin/movies,jellyfin/shows,jellyfin/music,\
  couchdb/data,couchdb/config,\
  matrix/synapse,matrix/postgres,matrix/media,\
  ebooks/library,ebooks/config,\
  spokenword/audiobooks,spokenword/podcasts,spokenword/metadata,spokenword/config,\
  portainer/data,\
  backups}
sudo chown -R $USER:$USER /mnt/data
```

Cabinet's subdirectories (`/mnt/data/cabinet/{data,media,consume,export,postgres}`) are not created at stage 1 because the cabinet stack does not run yet.

When you advance to stage 2 or 3, the path stays the same; only the underlying storage shape changes (single LUKS drive at stage 2, LUKS-encrypted RAID1 mirror at stage 3, both mounted at `/mnt/data`).

### Data posture

The risk acceptance at stage 1 is: **if the disk dies tomorrow, nothing on the box is the only copy of itself.** This is true only because of how stage 1 is operated:

- **Immich**: ran as a *mirror* of your existing photo service (iCloud Photos, Google Photos, whatever you use now). Don't disable the upstream service. Don't delete originals from your phone. Immich is the trial; the upstream is still the source of truth.
- **Obsidian (CouchDB)**: your vault still lives on your laptop and is still backed up wherever you currently back it up. LiveSync to the homelab is one-way insurance, not the canonical store.
- **Matrix/Synapse**: starts fresh. No history is being imported from anywhere. If the disk dies, the room history goes with it. The implicit deal is that you're using Matrix at this stage as a "is this the chat product I want" trial, not as a permanent record.
- **Jellyfin**: media files are re-rippable (DVDs, downloads, whatever your source is). Re-ripping is annoying, not catastrophic.
- **Calibre-Web (ebooks)**: the canonical EPUB / PDF files still live wherever they live now (your laptop's Calibre library, your purchase history at the source store, etc.). Calibre-Web is a reader and OPDS endpoint, not the archive.
- **Audiobookshelf (spokenword)**: source files (Libro.fm downloads, ripped CDs, etc.) still exist outside the box. Listening progress is per-user state on the homelab; losing it means re-finding your spot in active books, which is annoyance, not catastrophe.
- **Portainer**: stateless from a data-loss perspective. Portainer's own config DB lives in a Docker volume and reconstructs in ~10 minutes from the compose file plus a new admin password. The Docker resources it manages (containers, volumes, networks) live in Docker and are unaffected by a Portainer wipe.

Cabinet (Paperless-ngx) is absent from this list because cabinet does not run at stage 1. Its data class would be "irreplaceable digital copies of physical documents I have shredded," which has no upstream mirror and therefore does not fit the stage-1 risk acceptance.

**Encryption: none.** No LUKS at stage 1. Without a separate data drive to LUKS-encrypt, the only option would be full-disk encryption on the OS drive, which means Dropbear-in-initramfs (a small but real ongoing maintenance burden on every kernel update) or physical access to the box at every reboot. Neither is justified at a stage where the data on the box is already a second copy of itself.

What this means for the realistic threat: someone steals the physical box. They get a copy of your photos, your notes, and your Matrix history. The photos are also in your upstream service; the notes are also on your laptop; the Matrix history is small and recent. Tailscale credentials on the box let them join the tailnet as that node until you remove it from the admin console (revocation takes about ten seconds, do this immediately). The cost of theft at stage 1 is annoyance, not data loss.

Stage 2 closes this gap by putting all the "would actually be sad to lose unencrypted" data on a LUKS volume.

### Cost

- PC: $150 to $250 one-time
- Domain: already owned ($10 per year going forward, but no new spend)
- Electricity: SFF PCs idle around 15 to 25 watts. At US average residential rates, that's $1.50 to $3 per month
- Everything else (Tailscale, Funnel, Let's Encrypt, Docker): free

Total to start: under $250 one-time, then ~$3 per month in electricity.

### Trigger to advance

Stage 1 ends when **either** of these is true:

- The internal disk hits ~70% full. (Capacity, not redundancy, is what forces stage 2.)
- Three to six months have passed and you're still using the apps regularly enough that "is this for me" is settled.

If neither happens, you might just stay at stage 1 forever, and that's a fine outcome. Stage 1 is a complete product.

## Stage 2: PC plus one extra drive plus B2

**Goal:** add storage capacity and a real backup story, without yet investing in the full redundancy stack. Still solo-you, no friends and family on it.

### Hardware add

One drive. Two reasonable shapes:

**Option A (preferred if your SFF has a free 3.5" bay): one new internal 3.5" drive.** A WD Blue, Seagate Barracuda, or similar 4 TB or 8 TB desktop drive runs $80 to $150. Internal beats external because:

- No USB-to-SATA bridge to fail.
- No external power brick.
- Quieter, since it shares the chassis fan curve.
- LUKS unlock is simpler (boot sequence sees it immediately).

**Option B (fallback if no internal bay or no SATA cable): one external USB 3.0 drive.** A 4 TB to 8 TB WD Elements or Seagate Expansion. Same price range. The trade-off is that you need to unlock LUKS at every reboot or disconnect/reconnect, and the USB bridge is an additional point of failure.

Either way, this is the drive that will hold photos and media. Notes (small) and chat (small) can stay on the internal NVMe.

### Why not the old laptop drives

You have ~2 TB of old 2.5" laptop drives. They are tempting and they are cheap (free, already owned). But:

- **Unknown remaining lifespan.** Laptop drives accumulate wear during their laptop life (shock, thermal cycles, idle/spin-up cycles), and drives that have been sitting in a drawer can fail on first spin-up. SMART data can hint but not promise.
- **Not rated for 24/7 duty.** Desktop drives aren't either, strictly, but they tolerate it better than 2.5" mobile drives.
- **Capacity per enclosure.** Each old drive is probably 500 GB to 1 TB. To get to 4 TB usable, you'd need four enclosures, four USB ports, four points of failure.
- **You said yourself you don't trust them for irreplaceable data long term.** That instinct is correct.

Possible roles for them anyway:

- **Holding pen for the migration.** When you move the data currently on those drives to your gaming PC's 2 TB free space, you can wipe them and use one of them temporarily during the homelab swap if it's convenient.
- **Tertiary stash.** If you really want to use them, put non-irreplaceable content on them (a Jellyfin library of re-rippable movies, scratch space). Not Immich photos, not Matrix media, not the CouchDB Obsidian vault.
- **Retire.** Genuinely fine. Old laptop drives have done their tour.

### Migrating the gaming PC drives' current data

This is a separate workstream from the homelab stages, but you asked about it so:

1. Pick what you actually want to keep from the old laptop drives. Exclude `node_modules`, application caches, downloaded installers, `.git` directories of old projects you no longer touch, system folders from old Windows installs. A rough categorization of "documents, photos, project source, music" and a `rsync --dry-run` to estimate sizes will tell you whether 2 TB of free gaming-PC space is enough.
2. Copy to the gaming PC. Verify with a checksum spot-check (`shasum` a handful of files on both sides) before formatting anything.
3. The old laptop drives are now free for whatever role above you pick, or for retirement.

### What gets encrypted

LUKS2 on the stage-2 drive. Argon2id passphrase, the same model documented in `docs/encryption-at-rest.md`.

If the drive is internal: the unlock at every reboot uses the same manual SSH procedure as stage 3, no change.

If the drive is external USB: unlock happens when you physically attach the drive (which is usually once, when you set it up, and then again only after a power loss). Slightly more friction at reboot, but the steady state is identical.

OS disk stays plaintext, same reasoning as the main encryption doc. Notes and chat (the data still on the internal NVMe at stage 2) is small enough that "encrypt the OS disk too" remains a poor trade. If this bothers you, the right move is to skip ahead to stage 3 where the mirror holds everything that matters.

### Backups

Backblaze B2 turns on at this stage. Restic with the existing scripts in `backups/`. Weekly snapshots of:

- Postgres dumps for Immich, Synapse, and Paperless
- CouchDB `_all_dbs` dump
- Immich originals
- Matrix media store
- The ebooks library at `/mnt/data/ebooks/`
- The spokenword libraries at `/mnt/data/spokenword/` (audiobook files included; treated Obsidian-class)
- The cabinet (Paperless) data, media, and consume directories at `/mnt/data/cabinet/`
- The Portainer Docker volume (small, contains admin user and environment definitions)
- `/etc` and `/srv` configs

Skip: Jellyfin media (re-rippable, also too large for B2 to be cost-effective), cache directories, transcode scratch.

### What also turns on at stage 2

Cabinet (Paperless-ngx) deploys for the first time at stage 2. It does not exist at stage 1. The trigger to actually use cabinet for irreplaceable archival (shredding the physical original) is the existence of off-site B2 backup, which is exactly what stage 2 introduces.

Expected B2 spend at stage-2 scale (tens of GB of irreplaceable data): $1 to $3 per month, plus pennies per restore. Verify after the first full backup completes.

The local restic-to-USB target from the stage-3 design is *not* yet present. Stage 2 is B2-only. This is acceptable because:

- The data is already in two places: on the homelab drive, and in B2. That's 2-2-1 (two copies, two media, one off-site), not full 3-2-1, but a meaningful jump over stage 1.
- The cost of adding the USB local target is small and is exactly what stage 3 adds.

### Cost add

- Drive: $80 to $150 one-time
- B2: $1 to $3 per month
- (External USB enclosure if going option B: $20 to $40)

### Trigger to advance

Stage 2 ends when **any** of these is true:

- The stage-2 drive hits ~70% full.
- Friends or family want access. (This is the load-bearing trigger, see below.)
- A year passes with continued regular use.

## Stage 3: server-grade mirror plus full backup

This is the steady state the rest of the docs describe. Two NAS-rated drives (WD Red Plus, Seagate IronWolf) in mdadm RAID1, LUKS2 with Argon2id on the mirror, restic to USB nightly plus B2 weekly.

Stage 3 specifically corresponds to:

- `docs/initial-plan.md` (now historical scaffolding but the architecture stands)
- `docs/security-audit.md` (the threat-model commitments assume stage 3 data posture)
- `docs/encryption-at-rest.md`
- `README.md` bootstrap order from step 5 onward

### Why friends and family at stage 3 only

The moment someone else's photos, notes, or chat history live on the box, "it dies and I lose stuff" becomes "it dies and I lose stuff that wasn't mine to lose." That's a different commitment level.

Stage 3 gives you:

- Drive redundancy (RAID1 survives a single drive failure with zero data loss)
- Two backup destinations (local USB + off-site B2)
- LUKS on the data layer
- The verified-restore quarterly routine in `docs/security-audit.md`

Stage 2 has none of those except the cloud half of the backup story. Stage 1 has none of them at all. Inviting others before stage 3 is a promise the architecture can't yet keep.

### Migration from stage 2

Straightforward. The stage-2 drive becomes the local restic USB target, which is exactly the role it would have at stage 3 anyway.

1. Install the two NAS drives.
2. `bootstrap/mdadm-mirror.sh` to create the LUKS-encrypted mirror at `/mnt/data`.
3. Stop the app stacks. Rsync the stage-2 data directories into the new mirror structure at `/mnt/data/<app>/`.
4. Update each app's `docker-compose.yml` volume mounts from the stage-2 path to `/mnt/data/<app>/`. Start the stacks. Verify.
5. The (now empty) stage-2 drive gets reformatted and mounted at `/mnt/backup`. Initialize the restic USB repo against it. The B2 repo from stage 2 carries forward unchanged.
6. Quarterly restore drill goes on the calendar.

### Cost add

- Two NAS drives (4 TB each is the sweet spot for this scale, scale up if needed): $200 to $300 total
- B2 ongoing: now closer to $3 to $6 per month depending on total backed-up size

### What stops being optional

At stage 3, the deferred items from the original scaffolding (`docs/scaffolding-summary.md`) are no longer deferrable for a friends-and-family-grade service:

- Quarterly restore drill, actually performed
- Monthly `docker compose pull` (security updates for the apps)
- Drive health monitoring (SMART checks, alerting on `mdadm --detail` showing degraded state)
- Tested LUKS passphrase recovery (you, your password manager, and somewhere your spouse or a sibling can find it if you can't)

## Skipping stages

The stages exist to defer spend, not to gate. If you already know you want this, jumping straight to stage 3 is fine. Some plausible scenarios:

- **Already committed, just spreading the spend over a couple of months:** stage 1 to stage 3 directly, skipping stage 2. Wait to invite friends and family until stage 3 is fully bootstrapped and the quarterly restore drill has happened at least once.
- **Want a specific friend on it soon (you, your partner, one sibling):** stage 3 directly. Don't stage-2 with shared data, the redundancy isn't there.
- **Only want photos and notes, never video:** stage 2 might be the end state, not a way-station. A single drive plus B2 is honestly fine for tens of GB of photos and a CouchDB / Synapse pair, especially if you stay solo. Skip stage 3 entirely.

## What to write down when advancing a stage

A short paragraph in `docs/decisions.md`:

- What stage you moved from and to
- What triggered it (capacity, time, friends-and-family ask)
- Anything that surprised you (data ended up bigger than expected, an app misbehaved during migration, a drive was DOA)

This becomes the running history of the build and the input to the next decision if anyone asks "should I do what you did."
