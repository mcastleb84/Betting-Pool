# Pool Board

Betting pools with friends: buy-ins, who's in, the pot, payouts and a live game chat. Works in any browser and installs like an app on phones and computers.

## Setup (once)

1. In Supabase, open **SQL Editor → New query**, paste `pool-setup.sql`, and run it.
2. Do the same with `chat-setup.sql` (game chat) and `sports-setup.sql` (sport tabs).
3. In GitHub, go to **Settings → Pages**, set the source to **Deploy from a branch**, branch **main**, folder **/ (root)**, and save.

## Getting the app

- **Android / Chrome / Edge:** open the site and tap **Get the app** (or Install in the browser menu).
- **iPhone / iPad:** open the site in Safari, tap **Share → Add to Home Screen**. The **Get the app** button shows these steps.

## Files

- `index.html` – the app
- `config.js` – Supabase connection (publishable key only)
- `manifest.webmanifest`, `sw.js`, `icons/` – what makes it installable
- `pool-setup.sql`, `chat-setup.sql`, `sports-setup.sql` – database setup
