# welcome

Public landing page served at the root of `jackalope.network`. Single Vite + React build, no runtime on the server (Caddy serves the static `dist/`).

The page mirrors the visual language of the portfolio at `jackmcknight.dev` so the two sites feel related when you arrive from one to the other.

## What it does

- Hero block with a short bio in the same Tokyo Night palette and FiraCode type as the portfolio.
- Tile grid for each user-facing self-hosted app (Immich, Jellyfin, Obsidian/CouchDB, Matrix, Calibre-Web, Audiobookshelf, Paperless-ngx). Operator-only services (Portainer) are deliberately not listed here.
- Each tile is a link to its app's tailnet-only subdomain.
- On first load, a client-side probe checks whether the browser can reach a tailnet-only endpoint (`probe.jackalope.network/ok`). Two outcomes:
  - **On the tailnet:** tiles are fully colored and clickable, banner says "All apps are live."
  - **Off the tailnet:** tiles render with a "tailnet only" badge, are visually dimmed, and are not clickable. Banner explains why.
- Light/dark theme toggle, default follows the user's system preference, choice persists in `localStorage`.

## Local development

```bash
cd welcome
npm install
npm run dev
```

Open `http://localhost:5173`. The tailnet probe will time out and you'll see the off-tailnet rendering, which is what you want for layout work.

## Build for production

```bash
cd welcome
npm install
npm run build
```

Output lands in `welcome/dist/`. That directory is gitignored.

## Deploy

Three paths. The Netlify path is what is used as a placeholder while the home server hardware is being assembled. The other two are for once the home server is live.

### Netlify (placeholder, current)

Config lives in `netlify.toml` at the repo root. Setup is one-time:

1. Push this repo to GitHub.
2. In Netlify, "Add new site" -> "Import from GitHub", pick the repo.
3. Netlify reads `netlify.toml`, knows to build under `welcome/` with `npm run build`, and serves `welcome/dist/`. Accept defaults.
4. The site is live at `<site-name>.netlify.app` once the first build finishes (about a minute).

Optional: in Netlify "Domain settings", add `jackalope.network` as a custom domain. Netlify issues a Let's Encrypt cert automatically and tells you the DNS record to set. In Porkbun, point the apex at the Netlify hostname (CNAME if your registrar supports apex CNAMEs / ALIAS / ANAME, otherwise follow Netlify's instructions for an A record to their load balancer).

Every push to the default branch triggers a new build and deploy. No CI to configure.

**Off-tailnet rendering during the placeholder window:** the tailnet probe will fail (the server is not yet running, so `probe.jackalope.network` does not resolve), so every tile renders dimmed with a "tailnet only" badge. That is the correct signal for a placeholder: the services exist conceptually, they are not yet reachable. When the server comes up and DNS is repointed, the tiles will go live automatically with no code change.

### Build on the server (post-hardware)

### Build on the server (post-hardware)

```bash
# On the server:
cd /srv/welcome
git pull
npm ci
npm run build
```

Caddy is already configured to serve `/srv/welcome/dist`. No restart needed; Caddy reads files on demand.

Requires Node and npm installed on the server. Add to `bootstrap/debian-setup.sh` or install ad hoc with the nodesource setup script.

### Build on laptop, rsync `dist/` over (post-hardware)

```bash
# On laptop:
cd welcome
npm run build
rsync -avz --delete dist/ jack@<tailnet-ip>:/srv/welcome/dist/
```

This keeps Node off the server, which is cleaner. Trade-off is that you cannot edit content from the server.

Pick whichever fits your workflow. The "build on the server" path is suggested for v1 because it lets you iterate without leaving SSH.

## Caddy site block

The site block for the welcome page lives in `caddy/Caddyfile` under the `jackalope.network` (root) entry. It serves `/srv/welcome/dist` as static files. The probe endpoint is a separate site block at `probe.jackalope.network` that returns `200 OK` with the CORS headers needed for the cross-origin fetch from the welcome page.

## Adding a tile

Edit `src/data/tiles.js` and add an entry. Rebuild. Each entry has:

```js
{
  id: 'shortname',
  title: 'Display title',
  app: 'Underlying app name',
  description: 'One-sentence description.',
  href: 'https://shortname.jackalope.network',
  accent: 'accent' | 'cyan' | 'purple' | 'green',
}
```

To add a new accent color, add the matching `.accent_xxx` rule in `src/components/Tiles.module.css`.
