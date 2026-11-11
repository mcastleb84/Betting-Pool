# Pool Board

Betting pools with friends: buy-ins, who's in, the pot, payouts and a live game chat. Works in any browser and installs like an app on phones and computers.

## Setup (once)

1. In Supabase, open **SQL Editor → New query**, paste `pool-setup.sql`, and run it.
2. Do the same with `chat-setup.sql` (game chat), `sports-setup.sql` (sport tabs) and `payments-setup.sql` (PayPal, Cash App and Venmo buy-in buttons).
3. In GitHub, go to **Settings → Pages**, set the source to **Deploy from a branch**, branch **main**, folder **/ (root)**, and save.

## Google and Apple sign-in (once)

The buttons are on the log-in screen; each one starts working once it's turned on in Supabase. Your callback URL for both is
`https://qbyqkngwhpemrgzvykdd.supabase.co/auth/v1/callback`.

**Allow your site to come back after sign-in:** Supabase → Authentication → URL Configuration → add `https://mcastleb84.github.io/**` under Redirect URLs.

**Google (free):**
1. Google Cloud Console → APIs & Services → OAuth consent screen: set an app name and your email.
2. Credentials → Create credentials → OAuth client ID → Web application. Under Authorized redirect URIs paste the callback URL above.
3. Copy the Client ID and Client secret into Supabase → Authentication → Sign In / Providers → Google, turn it on, save.

**Apple (needs an Apple Developer account, $99/year):**
1. developer.apple.com → Certificates, IDs & Profiles → Identifiers: create an App ID with Sign in with Apple, then a Services ID (this is your Client ID).
2. On the Services ID, turn on Sign in with Apple; domain `qbyqkngwhpemrgzvykdd.supabase.co`, return URL = the callback URL above.
3. Keys → create a key with Sign in with Apple, download the .p8 file.
4. Supabase → Authentication → Sign In / Providers → Apple: turn it on, enter the Services ID, and generate the secret from your Team ID, Key ID and .p8 file. Apple secrets expire after 6 months, so set a reminder to make a new one.

Someone who used email before and then taps Google or Apple with the same email lands in the same account.

## Buy-in payments

When you create or edit a pool, fill in your PayPal.me username, Cash App $cashtag and/or Venmo username. Players get a button for each one that opens the app with the buy-in amount already filled in. After paying, a player taps **I paid with…** so you know which app to check; their name shows "Says sent" until you tap **Paid**. The money goes straight from them to you; the site never holds it.

## Getting the app

- **Android / Chrome / Edge:** open the site and tap **Get the app** (or Install in the browser menu).
- **iPhone / iPad:** open the site in Safari, tap **Share → Add to Home Screen**. The **Get the app** button shows these steps.

## Files

- `index.html` – the app
- `config.js` – Supabase connection (publishable key only)
- `manifest.webmanifest`, `sw.js`, `icons/` – what makes it installable
- `pool-setup.sql`, `chat-setup.sql`, `sports-setup.sql`, `payments-setup.sql` – database setup
