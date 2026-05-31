// Tile definitions for the launcher grid. To add a new app, drop in
// a new entry and rebuild. Add the logo SVG under public/icons/ first.

export const tiles = [
  {
    id: 'immich',
    app: 'Immich',
    role: 'Photos',
    href: 'https://immich.jackalope.network',
    icon: '/icons/immich.svg',
    color: '#FA2C36',
  },
  {
    id: 'jellyfin',
    app: 'Jellyfin',
    role: 'Video',
    href: 'https://jellyfin.jackalope.network',
    icon: '/icons/jellyfin.svg',
    color: '#00A4DC',
  },
  {
    id: 'obsidian',
    app: 'Obsidian',
    role: 'Notes',
    href: 'https://couchdb.jackalope.network/_utils/',
    icon: '/icons/obsidian.svg',
    color: '#7C3AED',
  },
  {
    id: 'element',
    app: 'Element',
    role: 'Chat',
    href: 'https://element.jackalope.network',
    icon: '/icons/element.svg',
    color: '#0DBD8B',
  },
];

export const brand = {
  name: 'Jackalope Network',
  domain: 'jackalope.network',
  tagline: 'A small set of services, self-hosted at home.',
  bio: [
    `Everything here runs on one box in my apartment. Photos, video, notes, and chat, all behind Tailscale, all owned and operated rather than rented.`,
    `The code, the runbook, and the security audit live in the repo below.`,
  ],
  repo: 'https://github.com/mcknijak/homelab-server',
  portfolio: 'https://jackmcknight.dev',
};
