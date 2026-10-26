# Linkshelf

**All your links. One page that's actually yours.**

Linkshelf is a link-in-bio builder: sign up, claim a username, add your links, pick a look, and share one page. It counts how many times each link gets clicked.

Built by Armen ([ArMenace](https://armenace.github.io)) with AI, then reviewed, tested and hardened by hand.

**Live app:** `https://armenace.github.io/linkshelf/`
**Example page:** `https://armenace.github.io/linkshelf/page.html?u=armen`

## Features

- Email and password accounts (Supabase Auth, with email confirmation and "forgot password")
- Claim a unique username, edit your name and bio
- Change your username without breaking old links: they redirect to the new one
- Delete your account and everything in it
- Add, edit, reorder and delete links, with a live phone preview while you type
- Five themes: Cobalt, Paper, Night, Lemon, Mint
- Click counter on every link
- Works on phones, keyboard-friendly, respects "reduce motion"

## How it's built

| Part | What it does |
| --- | --- |
| `index.html` | The app: sign in, claim a username, editor with live preview |
| `page.html` | The public page visitors see (`page.html?u=username`) |
| `shared.js` | Supabase connection, themes, and the page renderer used by both pages |
| `shelf.css` | The look of a public page and its five themes |
| `schema.sql` | Database tables, security rules, and the click counter |

No build step and no framework: plain HTML, CSS and JavaScript on GitHub Pages, with [Supabase](https://supabase.com) (Postgres + Auth) as the backend.

## Security

The publishable key is public by design, so all protection lives in the database:

- **Row Level Security:** anyone can read pages, but only the owner can create, edit or delete their own profile and links.
- **Click counts are hard to fake.** The `clicks` column can only change through `increment_click()`. Owners can't set it when creating or editing a link, and each visitor counts at most once per link per hour (the database keeps a hash of their IP address for an hour, never the address itself). Someone with many IP addresses can still add clicks, so treat the numbers as a good guide, not proof.
- **No `javascript:` links.** URLs must start with `http://` or `https://`, checked in the browser *and* in the database.
- **No XSS.** All user text is inserted with `textContent`, never `innerHTML`.
- **No impersonation.** Usernames are limited to `a-z`, `0-9` and `_`, names like `admin` or `support` are reserved, and when you rename yourself your old name stays yours (your 3 most recent old names), so nobody can take over links you already shared.
- **Pinned library.** `supabase-js` is loaded at an exact version with an integrity hash, so the browser refuses it if the CDN ever serves something else.

All rules were tested against a local Postgres (PGlite): the tests try to edit another user's page, preset and fake clicks, claim reserved and retired usernames, and delete someone else's account, and every attempt is blocked.

## Updating the database

`schema.sql` is safe to run more than once. After pulling a new version, open **SQL Editor → New query**, paste all of it again and click **Run**. Your existing pages and links are kept.

## Run your own copy

1. **Create a Supabase project** (free) at [supabase.com](https://supabase.com).
2. **Create the database:** open **SQL Editor → New query**, paste all of `schema.sql`, and click **Run**.
3. **Get your keys:** click **Connect** (or **Settings → API Keys**), then copy the **Project URL** and the **publishable key** (`sb_publishable_…`).
4. **Paste them** at the top of `shared.js`:
   ```js
   const SUPABASE_URL = "https://your-project.supabase.co";
   const SUPABASE_KEY = "sb_publishable_...";
   ```
   Never use a *secret* or *service_role* key here.
5. **Put it online:** push this repo to GitHub, then go to **Settings → Pages → Deploy from a branch → main → / (root)**.
6. **Fix the email links:** in Supabase, go to **Authentication → URL Configuration** and set **Site URL** to your live address, e.g. `https://armenace.github.io/linkshelf/`. The confirmation and password-reset emails both send people back there.

## Ideas for later

- Profile photo upload (Supabase Storage)
- Drag-and-drop reordering
- Clicks per day chart
- Custom colors on top of the themes
