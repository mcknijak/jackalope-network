# cabinet (Paperless-ngx)

Document archive with OCR, full-text search, autotagging, and email-driven ingestion. Reached at `cabinet.jackalope.network` on the tailnet.

> **Stage scope:** runs at stage 2 and stage 3 only. Skipped at stage 1 because the whole value proposition is "I trust this archive enough to shred the original," which requires a real backup story. Stage 2 gives restic to B2 weekly; stage 3 adds USB nightly. At stage 2, the data is on the single LUKS-encrypted data drive; at stage 3, on the LUKS-encrypted RAID1 mirror. Both meet the "shred the physical" bar.

## What it is

[Paperless-ngx](https://docs.paperless-ngx.com/) is the standard self-hosted document archive. It:

- OCRs every uploaded document via tesseract.
- Indexes the full text for search.
- Auto-tags using a combination of keyword/regex matching rules and an ML classifier that learns from your tagged documents.
- Pulls documents from a watched folder (the "consume" directory), from email (IMAP polling), and from direct API uploads (which is how the iOS app sends things).

The stack here runs three containers: Paperless itself, a dedicated Postgres, and a dedicated Redis. They share an internal Docker network (`cabinet-internal`) that is not on the `proxy` network, so only Paperless itself is reachable through Caddy.

## First-time setup

1. Create the data directories:

   ```bash
   sudo mkdir -p /mnt/data/cabinet/{data,media,consume,export,postgres}
   sudo chown -R 1000:1000 /mnt/data/cabinet
   ```

2. Generate secrets and write `.env`:

   ```bash
   cd /srv/cabinet
   cat > .env <<EOF
   PAPERLESS_DB_PASS=$(openssl rand -hex 24)
   PAPERLESS_SECRET_KEY=$(openssl rand -hex 50)
   EOF
   chmod 600 .env
   ```

   Rotating `PAPERLESS_SECRET_KEY` later invalidates existing sessions; rotating `PAPERLESS_DB_PASS` requires a manual `ALTER USER` against Postgres first.

3. Bring up the stack:

   ```bash
   docker compose up -d
   ```

4. Create the superuser (this is the first user that can log in to the web UI):

   ```bash
   docker compose exec paperless python3 manage.py createsuperuser
   ```

   Username, email, password. The password should come from your password manager.

5. Open `https://cabinet.jackalope.network` and log in. The empty UI greets you with no documents yet.

## Seed the tag taxonomy

Paperless is most useful when its tags reflect how *you* think about your documents, not what someone else's tag list says. A starter set worth creating up front (Settings -> Tags -> New):

- `receipt`: purchases you want a copy of
- `warranty`: anything with a coverage period worth tracking
- `manual`: appliance / device documentation
- `tax`: anything tax-relevant for a given year
- `medical`: health and insurance docs
- `contract`: leases, ToS you accepted, signed agreements
- `statement`: bank / brokerage / utility statements
- `id`: identity documents (driver's license scans, passport, etc.)

Also create a few **correspondents** (Settings -> Correspondents) for merchants and providers you see repeatedly: Amazon, your bank, your utility company, your landlord, your doctor's office. Paperless auto-suggests these on future documents from the same sender.

Both tags and correspondents support automatic matching via three modes:

- **Any of these words**: simplest; matches if any keyword is present.
- **All of these words**: stricter.
- **Regular expression**: most flexible. Use for sender domains in email rules (see below).

A few rules pay for themselves immediately:

- Tag `tax` matching "1099", "W-2", "tax", "IRS", "form 8606" (any-of).
- Tag `warranty` matching "warranty", "limited warranty", "coverage period" (any-of).
- Tag `receipt` matching "order #", "receipt", "thank you for your purchase" (any-of).
- Correspondent "Amazon" matching the regex `@(amazon|amzn)\.com` if you also use the email rule below.

The ML classifier under Settings -> Configuration -> Auto-matching runs nightly and gets better as you correct mistakes manually.

## iOS scanning: Paperless Mobile

The recommended iOS app is **Paperless Mobile** (free, on the App Store). It uses Apple's VisionKit scanner (same engine as Notes), uploads via Paperless's REST API, and lets you pick tags / correspondents at upload time so they're applied immediately rather than waiting for the auto-matchers.

Setup:

1. Install Paperless Mobile.
2. Server URL: `https://cabinet.jackalope.network`.
3. Log in with your Paperless username and password.
4. The app uses the iOS document scanner. Point at a page, the corners auto-detect, multi-page docs are one-tap. The scan goes straight into Paperless's consume queue.

The phone has to be on the tailnet for this to work (Tailscale app installed and connected). Same constraint as everything else under `*.jackalope.network`.

## Email ingestion: receipts@jackalope.network

The point of the email path is **getting digital receipts out of your inbox and into the archive automatically**, with a human-review safety net so nothing important gets shredded silently.

The shape:

1. Whitelisted senders are consumed by Paperless instantly and the message is deleted from the mail server (the document is now safely in Paperless and on backups).
2. Non-whitelisted senders land in a `Review` folder where they sit for up to 30 days.
3. You skim `Review` periodically (weekly is plenty). To **approve** a message, move it to the `Approved` folder; Paperless picks it up on the next poll and ingests it. To **reject** a message, either ignore it (it auto-purges after 30 days) or move it to Trash manually for immediate cleanup.
4. A weekly host-side cron deletes anything in `Review` older than 30 days as the safety net.

Net result: your primary inbox stays clean, whitelisted receipts flow in untouched, and nothing gets deleted without you having a chance to see it first.

### Mailbox setup (one-time, at Porkbun)

1. In the Porkbun control panel for `jackalope.network`, add the **Email Hosting** product ($24/year as of writing). This makes Porkbun the MX for the domain and gives you real mailboxes.
2. Create a mailbox: `receipts@jackalope.network`. Pick a strong password and put it in your password manager.
3. Note the IMAP server hostname Porkbun shows on the mailbox page (typically `mail.porkbun.com`, port 993, IMAPS).
4. Log in to the Porkbun webmail (or any IMAP client) once and create two folders next to `INBOX`: `Review` and `Approved`. Paperless's mail rules will not auto-create folders on the server, so they have to exist before the rules can target them.

### Wire paperless to the mailbox

In the Paperless web UI:

1. Settings -> Mail accounts -> Add.
   - Name: `Receipts`
   - IMAP server: `mail.porkbun.com`
   - Port: `993`, SSL.
   - Username: `receipts@jackalope.network`
   - Password: the mailbox password.
   - Save and test the connection.

2. Settings -> Mail rules -> Add the **whitelist consume** rule (this one runs first):
   - Name: `Receipts (whitelist consume)`
   - Mail account: `Receipts`
   - Folder: `INBOX`
   - Order: `10` (runs before the catchall).
   - Filter from: `(amazon|amzn|paypal|stripe|squareup|backblaze|porkbun|tailscale|netflix|spotify)\.com$` (regex; extend over time).
   - Action: Consume document. Action on consumed: **Delete from server**.
   - Assign correspondent: From email address (Paperless will auto-create per-sender correspondents).
   - Assign tag: `receipt`.

3. Settings -> Mail rules -> Add the **catchall to Review** rule:
   - Name: `Catchall (move to Review)`
   - Mail account: `Receipts`
   - Folder: `INBOX`
   - Order: `20` (runs after the whitelist).
   - Filter from: leave blank (matches anything not caught by rule 1).
   - Action: Move. Move to folder: `Review`.
   - Do **not** consume.

4. Settings -> Mail rules -> Add the **approved consume** rule:
   - Name: `Approved (consume from review)`
   - Mail account: `Receipts`
   - Folder: `Approved`
   - Order: `30`.
   - Filter from: leave blank (anything you've moved into Approved is by definition trusted).
   - Action: Consume document. Action on consumed: **Delete from server**.
   - Assign correspondent: From email address.
   - Assign tag: `receipt`.

   This is the rule that turns the approval gesture (you, dragging a message into the Approved folder) into an actual Paperless ingestion. No additional action on your part needed beyond the move.

### The review workflow (your weekly habit)

1. Open the `receipts@jackalope.network` mailbox in Porkbun webmail (or any IMAP client logged in as that user).
2. Open the `Review` folder.
3. For each message:
   - **Worth keeping?** Move to `Approved`. Paperless ingests on its next poll (typically within 10 seconds; the `PAPERLESS_CONSUMER_POLLING` setting in `compose.yml` controls this).
   - **Not worth keeping?** Leave it alone; it auto-purges in 30 days. Or move to Trash for immediate cleanup.
4. Optional but recommended: if a sender shows up in `Review` repeatedly and you always approve, add its domain to the whitelist regex in the rule from step 2. Future messages skip Review entirely.

### Host-side Review purge (safety net)

Paperless does not have a "delete from a folder after N days" primitive, so this is a separate cron. The simplest path is a weekly systemd timer that runs:

```python
# /usr/local/sbin/cabinet-review-purge.py
import imaplib, datetime, os
M = imaplib.IMAP4_SSL("mail.porkbun.com")
M.login("receipts@jackalope.network", os.environ["MAILBOX_PASS"])
M.select("Review")
cutoff = (datetime.date.today() - datetime.timedelta(days=30)).strftime("%d-%b-%Y")
typ, data = M.search(None, f'(BEFORE {cutoff})')
for num in data[0].split():
    M.store(num, "+FLAGS", "\\Deleted")
M.expunge()
M.logout()
```

Store `MAILBOX_PASS` in `/etc/cabinet-mailbox.env` (root-owned, 0600), and wrap the script in a systemd `.service` + weekly `.timer` pair. Document the units alongside the restic ones if you write them; they belong to the cabinet stack conceptually.

Tune the 30-day window to your review cadence. If you actually look at Review weekly, 14 days is enough. If you let it slide for a month at a time, bump to 45 or 60. The window should be long enough that you'll always have caught up before anything ages out.

### Forwarding receipts to it

Once `receipts@jackalope.network` is live, configure your existing email tool to forward merchant receipts there. Two reasonable approaches:

- **Filter-based forwarding.** Most mail clients can match on sender domain and auto-forward. Set up filters for the merchants in your whitelist.
- **Manual forwarding for one-offs.** Forward any receipt you want archived. Whitelisted senders flow straight into Paperless; non-whitelisted ones land in Review for you to triage on the next pass.

## Things to know

- **OCR is CPU-heavy.** First-time ingestion of a backlog can pin a core for hours. Run the initial bulk import overnight.
- **The `consume` directory** is a watched folder. Anything dropped in `/mnt/data/cabinet/consume/` gets ingested. The iOS app uses the API directly; this is the path for "I have a folder of legacy PDFs I want to bulk-import."
- **Document storage layout.** Paperless stores OCR'd documents under `/mnt/data/cabinet/media/`, named by year and document ID, not by your tags. The tags / correspondents / search are the access mechanism; don't go looking for "your folder of receipts" under media.
- **Backups.** `/mnt/data/cabinet/` (all subdirs) is backed up by restic at stages 2 and 3. The Postgres data directory is captured raw, and the restic script's `pg_dump` step should be extended to include the paperless database too (see `backups/README.md`).
- **Trust boundary.** The Postgres and Redis containers are on the internal `cabinet-internal` Docker network only, not on `proxy`. Caddy can reach Paperless, but nothing else can reach Postgres / Redis.
