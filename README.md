# Linkshelf

**All your links. One page that's actually yours.**

Linkshelf is a link-in-bio builder: sign up, claim a username, add your links, pick a look, and share one page. It counts how many times each link gets clicked.

Built by Armen ([ArMenace](https://armenace.github.io)) with AI, then reviewed, tested and hardened by hand.

**Live app:** `https://armenace.github.io/linkshelf/`
**Example page:** `https://armenace.github.io/linkshelf/page.html?u=armen`

## Features

- Email and password accounts (Supabase Auth, with email confirmation)
- Claim a unique username, edit your name and bio
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
- **Click counts can't be faked.** The `clicks` column can only change through `increment_click()`, which adds exactly 1. Even owners can't edit it.
- **No `javascript:` links.** URLs must start with `http://` or `https://`, checked in the browser *and* in the database.
- **No XSS.** All user text is inserted with `textContent`, never `innerHTML`.
- Usernames are limited to `a-z`, `0-9` and `_`, checked in both places.

All rules were tested against a local Postgres: the test tries to edit another user's page, fake clicks, and insert `javascript:` links, and every attempt is blocked.

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
6. **Fix the confirmation email link:** in Supabase, go to **Authentication → URL Configuration** and set **Site URL** to your live address, e.g. `https://armenace.github.io/linkshelf/`.

## Ideas for later

- Profile photo upload (Supabase Storage)
- Drag-and-drop reordering
- Clicks per day chart
- Custom colors on top of the themes
