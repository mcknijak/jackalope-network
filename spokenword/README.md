# spokenword (Audiobookshelf)

Audiobook and podcast server, reached at `spokenword.jackalope.network` on the tailnet.

> **Stage scope:** runs at every stage. At stage 1 the libraries live at `/mnt/data/spokenword/{audiobooks,podcasts}` on the OS disk; at stage 2 on the single LUKS-encrypted data drive; at stage 3 on the LUKS-encrypted RAID1 mirror. Backed up by restic starting at stage 2 (B2 weekly) and stage 3 (USB nightly + B2 weekly). At stage 1 there is no backup; the trial-mode assumption is that audiobook source files exist elsewhere (your original purchases, ripped CDs, Libro.fm downloads, etc.).

## What it is

[Audiobookshelf](https://www.audiobookshelf.org/) is the de facto self-hosted audiobook + podcast server. It does:

- Library scanning with reasonably good audiobook metadata lookups (Audible, Google Books, OpenLibrary fallbacks).
- Per-user listening progress, synced across devices.
- Podcast subscription, download, and playback.
- A first-party iOS app, an Android app, and a web player.
- An OPDS-style API for third-party clients.

## First-time setup

1. Create the library directories:

   ```bash
   mkdir -p /mnt/data/spokenword/{audiobooks,podcasts,metadata,config}
   ```

2. Bring up the stack:

   ```bash
   cd /srv/spokenword && docker compose up -d
   ```

3. Open `https://spokenword.jackalope.network` from a tailnet device. The first-run wizard:
   - Creates the root admin account. Pick a strong password (`openssl rand -hex 16` is fine). Store it in your password manager.
   - Asks you to add libraries. Add two:
     - **Audiobooks**: folder `/audiobooks` (which is `/mnt/data/spokenword/audiobooks` on the host).
     - **Podcasts**: folder `/podcasts`, library type "podcast."

4. Drop audiobook files into `/mnt/data/spokenword/audiobooks/` and hit "Scan library." Audiobookshelf expects one folder per book, ideally with `[Author] - [Title]` naming, but it's forgiving.

## Audiobook sources

- **Libro.fm and other DRM-free purchases**: drop the M4B / MP3 directly. Works perfectly.
- **Ripped CDs**: same. Tag with MusicBrainz Picard or similar first if you want clean metadata.
- **LibriVox**: free public-domain audiobooks. Drop them in.
- **Audible (`.aax`)**: DRM-encumbered. Audiobookshelf does not decode AAX directly. The standard workflow is to convert AAX to M4B locally using a tool like [AAXtoMP3](https://github.com/KrumpetPirate/AAXtoMP3) or [OpenAudible](https://openaudible.org/) (the latter is paid and uses your Audible activation bytes); then drop the M4B in.

## Podcasts

In the web UI, go to your Podcasts library -> Add. You can paste an RSS feed URL directly, or search the iTunes podcast catalog. Audiobookshelf polls the feed on a schedule and downloads new episodes into `/mnt/data/spokenword/podcasts/<show>/`.

A handful of defaults worth tweaking under Settings -> Libraries -> Podcasts:

- **Auto-download new episodes**: on, if you want a true podcatcher.
- **Max episodes kept**: set a per-show cap if you don't want every show to grow forever. Three or five recent episodes per show is plenty if you also listen actively.

## iOS app

There's a first-party app called **Audiobookshelf** in the App Store (free, open source). Setup:

1. Install the app.
2. Tap "Add server."
3. Server address: `https://spokenword.jackalope.network`.
4. Username and password: your Audiobookshelf admin credentials.

The app supports offline download per book, variable playback speed, sleep timer, and progress sync. The web player and the iOS app stay in sync via the server, so you can start a book in the browser and pick up on the phone.

## Things to know

- **Container runs as root** (Audiobookshelf doesn't have a great non-root story out of the box). The data directories on the host end up root-owned. If you ever need to inspect or move files by hand, `sudo` your way in. If this bothers you, set `user: "1000:1000"` in `compose.yml` and pre-create the directories with matching ownership.
- **Library scans are not instantaneous.** A library of a few hundred books takes a minute or two to scan. The web UI shows progress.
- **Per-user accounts**: Audiobookshelf supports multiple users with separate listening progress. The admin account you created is the operator; add additional accounts under Settings -> Users when household / friends-and-family time comes (stage 3).
- **Backups.** Restic captures `/mnt/data/spokenword/` whole at stages 2 and 3. Per the decision to treat audiobooks as Obsidian-class despite being technically re-acquirable: the media files themselves go into restic too, not just the metadata. This costs disk and B2 dollars but means a restore is one-shot rather than "restore metadata, then re-rip everything."
