# Why Tailscale (instead of just app-level logins)

A reasonable question to ask: every app on this stack already has a real login system. Why not expose them to the public internet directly and rely on Immich's password, Jellyfin's password, Element's account, and CouchDB's basic auth? Why add a whole separate access layer with Tailscale?

This doc records the answer so it doesn't have to be re-derived every time the trade-off comes up.

## What Tailscale actually buys you

Tailscale's design property that matters here: a device that is not enrolled in the tailnet does not hold a WireGuard key, and without that key it cannot even initiate a TCP handshake with the server. The app's login form never gets a request. From the public internet, the services do not appear to exist (the `100.64.0.0/10` CGNAT address they resolve to is not routable).

Tailscale themselves position this as defense-in-depth on top of per-app auth, not as a replacement for it (https://tailscale.com/blog/how-tailscale-works). The pitch is strongest for "legacy or non-web services that are no longer maintained," but the same logic applies to any web app where the cost of a single auth bug is much larger than the friction of installing one client.

## The argument from CVE history

The hard evidence for "do not just trust app-level auth" is the CVE record on the four apps in this stack over roughly the last two years. Every one of them shipped at least one auth-bypass or privilege-escalation bug in that window:

- **Immich**: CVE-2025-43856 (CVSS 8.8) was an OAuth2 account-hijack via a missing state parameter, fixed in 1.132.0. CVE-2026-23896 let API keys escalate to admin, fixed in 2.5.0.
- **Jellyfin**: CVE-2026-35031 was an authenticated path-traversal that wrote arbitrary files as root, giving RCE. CVE-2026-35032 was an SSRF / local-file-read in LiveTV, exploitable by any logged-in user because `EnableLiveTvManagement` defaults to true. CVE-2024-43801 was a stored XSS via SVG profile pic. Jellyfin has a long-running reputation for unguarded endpoints; this is the weakest of the four.
- **CouchDB** (Obsidian sync backend): CVE-2024-21235 was a privilege-escalation via the `security_admin_local` role. Default-install admin access has been an ongoing footgun. No new CVEs in 2025 or 2026, but the historical record is bad enough that putting a CouchDB instance directly on the internet is something you have to think hard about.
- **Synapse**: CVE-2025-30355 was a device-key validation issue (federation DoS). CVE-2024-37303 was an unauthenticated remote media download/cache abuse before 1.106.

Pattern: in any given year at least one of these four ships an unauthenticated or pre-auth bug. The window between the bug landing in upstream and your monthly `docker compose pull` is the window you are exposed. With Tailscale-only, an attacker first needs a WireGuard key from an enrolled device before they can even start trying to hit the buggy endpoint. That is a much smaller attack surface than "find a bug in any of four web apps before the operator's next patch cycle."

## What you give up by going Tailscale-only

Not nothing. The honest list of cases where app-login-only would actually be the better answer:

- Sharing with people who will not install Tailscale (extended family, casual viewers, anyone who is going to bounce if you send them an account-creation link).
- Native experiences on devices where the Tailscale client is awkward or absent: Chromecast, some smart TVs, car head units.
- Public link-sharing flows where the goal is "this URL just works" for a recipient who is not technical.
- Truly public services (a Jellyfin community, a federated Matrix homeserver).
- Setups where you have already invested in a hardened public surface (reverse proxy with WAF, fail2ban, Crowdsec, SSO) for other reasons and the marginal cost of adding one more app is low.

For this homelab, the actual user list is "me plus a small trusted few." The one share-with-outsiders flow is photo-album links. Everything else benefits from the Tailscale-only posture.

## Middle-ground patterns worth knowing

Three patterns come up repeatedly in the self-hosted community and are worth recording even if not used today.

### Tailscale Funnel

Funnel is Tailscale's feature for taking a single tailnet service and making it publicly reachable, with TLS certs and routing handled by Tailscale's edge (https://tailscale.com/kb/1223/funnel). No port-forward on the home gateway is needed. The traffic still terminates inside the tailnet but the originating client does not have to be on it.

For this stack, Funnel is a direct alternative to the planned Cloudflare Tunnel for `photos.jackalope.network`. Trade-offs vs Cloudflare Tunnel:

- **Funnel pros**: simpler (already have Tailscale running), no second account/dashboard to manage, no DNS dance, fewer moving parts.
- **Funnel cons**: no WAF or DDoS absorption, traffic still hits your home upload bandwidth, fewer log/analytics features. Bandwidth caps on the free tier.
- **Cloudflare Tunnel pros**: edge cache and DDoS protection, analytics, more battle-tested for high-traffic public services.
- **Cloudflare Tunnel cons**: another dependency, another config surface, exposes the domain's metadata to Cloudflare.

For a low-volume photo-share use case, Funnel is probably the better fit. Worth revisiting before standing up Cloudflare Tunnel. Open follow-up.

### Reverse proxy plus SSO (Authelia or Authentik)

Caddy or Traefik fronts every app and requires SSO (typically with MFA) before the app ever sees the request. Authelia is config-file driven and lightweight; Authentik is a full identity provider with a UI and group/role management. Either gives you a single login that gates everything.

This is the dominant "grown-up self-hosted" pattern when the apps need to be publicly reachable. It does not replace the value of Tailscale; it replaces "per-app login forms exposed to the internet." If the architecture ever moves toward "some services publicly available, some not," SSO at the reverse proxy is what unlocks that without N separate auth surfaces.

Not added to this stack today because the apps are not public-by-default. If that ever changes (for example, the family wants direct browser access to Immich), Authelia in front of Caddy is the next step, not opening ports directly.

### Split pattern: public-via-SSO for some, tailnet-only for others

Rather than "all public" or "all private," partition the apps by sensitivity. Synapse admin, CouchDB, and Immich library-admin paths stay tailnet-only; the Jellyfin web UI and Element web UI sit behind Authelia and are publicly reachable. This is the design a lot of larger homelabs end up at.

Worth re-evaluating if the user count grows or if direct browser access becomes important.

## The verdict for this homelab

Keep the default Tailscale-only posture. Add Funnel (or Cloudflare Tunnel) selectively for the one or two flows that genuinely need public reach, starting with photo sharing.

The CVE evidence is the load-bearing argument. The cost of being wrong about app auth is high (a bug in any of the four apps becomes a real exposure within whatever window separates upstream patch from your next `docker compose pull`). The cost of Tailscale-only is a one-time client install per friend. That trade is correct for the threat model in `docs/security-audit.md`.

If the friend-install friction ever turns into an actual problem, the next step is Funnel for the specific app where that friction lives, not flipping the whole architecture. If the architecture ever needs to be substantially more public, the next step after that is Authelia in front of Caddy, not opening ports.

## Considered and not adopted: unified jackalope.network SSO

A separate question from "Tailscale vs per-app login" is "Tailscale vs **one** unified login for the whole domain." Worth recording the analysis here because it sounds appealing and is easy to re-raise.

The pattern would be Authelia (or Authentik) doing forward-auth at Caddy. Every request to any `*.jackalope.network` host hits Caddy first; Caddy asks Authelia "is this session valid?" and either bounces the user to a single jackalope.network login page or forwards the request to the app with a `Remote-User` header. The app trusts the header because Caddy is the only thing it talks to.

End-user experience: one login at the domain level, one MFA setup, one password rotation policy, one audit log. Apps feel like part of one product instead of four separate self-hosted projects. No Tailscale client install required to use the apps from a browser.

### What it actually buys

- Single credential and MFA across all apps.
- Public reachability without exposing each app's individual login form (the only public auth endpoint is Authelia's, which is purpose-built for being on the internet).
- Friends can use any device or browser, including smart TVs and Chromecasts, without a Tailscale client install.
- MFA enforced even on apps with weak native MFA (Jellyfin's MFA story is the obvious example; Authelia papers over that).
- "Feels like jackalope.network the product" rather than four apps under one domain.

### The mobile-app trap that flips the calculus

Forward-auth gates HTTP requests at Caddy. **Native mobile apps do not honor forward-auth.** Element mobile, Immich mobile, Obsidian LiveSync, Jellyfin mobile all hit `/api/*` directly with their own auth headers (bearer tokens, basic auth, etc.). For SSO at the proxy you have two real options:

- **Block API paths too.** Mobile apps stop working entirely. Effectively useless for Immich and Jellyfin, where the mobile app is the primary way the service is used.
- **Allow API paths to pass through.** The app's own auth is what gates the mobile traffic. This is the only viable choice in practice.

In option two, you have publicly exposed the buggy code paths (the per-app `/api/*` surface) that the CVE record in this doc was the load-bearing reason to keep tailnet-only. Authelia gates the web UI (mostly secondary), but the mobile API surface stays publicly reachable and is still gated by app-level auth that has shipped pre-auth bugs in every one of these four apps over the last two years.

So unified SSO buys a real UX win but does not actually eliminate the risk that made the Tailscale-only choice correct. It hides that risk behind a nicer login page.

### The three honest architectures, ranked

1. **Tailscale-only (current).** Zero public surface for the apps. Mobile clients are protected because the apps are not reachable at all from off-tailnet. Cost: every user installs Tailscale.
2. **SSO at the proxy + public exposure.** One login experience, no client install. But mobile API traffic stays publicly exposed and relies on app-level auth. Adds Authelia plus its operational burden (Crowdsec rules, fail2ban, monitoring) on top.
3. **Hybrid: Tailscale-only by default, Authelia in front of Caddy for the specific apps you decide to also expose publicly.** Get the unified-login UX where it actually matters, keep the tailnet posture for the apps that do not benefit from public access.

### Decision (2026-05-28)

Kept architecture 1. Recorded architecture 2 as **considered and rejected for the unified-UX use case**: the apparent UX win does not extend to mobile clients, which are the primary access pattern for the most-used apps. Architecture 3 is documented here as the right next step **if** any specific app ever needs unified public-plus-web access in the future. Do not adopt architecture 3 prematurely just because the SSO pattern looks appealing.

### Triggers to revisit this decision

- A specific app is identified as needing public browser access for a real user (not hypothetical). At that point, add Authelia for that app only, do not flip the whole architecture.
- Tailscale-install friction is named by an actual user as a barrier (not assumed). Then evaluate whether Funnel (no install needed) covers the case before reaching for SSO.
- The user base grows to a size where per-device Tailscale enrollment is genuinely a scaling problem (10+ household users, regular guest access, etc.).

If none of those triggers happen, do not relitigate this.

## Cross-references

- `docs/security-audit.md`: full threat model and what's hardened
- `docs/networking.md`: how Tailscale, DNS, and Caddy fit together in this design
- `docs/decisions.md`: the running log; the access-model decision is recorded there
