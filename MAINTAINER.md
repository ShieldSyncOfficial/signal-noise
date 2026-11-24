# Maintainer guide: online accounts & live leaderboards

This guide is for the game owner (**shieldsyncofficial**). Players don't need it.

SIGNAL//NOISE uses **Supabase** (free tier) for:

- **Accounts:** unique usernames + 4-digit passcodes (case-insensitive, so "NightHawk" and "nighthawk" are the same name)
- **Cloud saves:** log in on any device and your whole profile and run in progress come with you
- **Live leaderboards:**
  - **Runs:** every run's total, posted automatically each time a player clocks out of a shift (unfinished runs included, marked LIVE)
  - **Careers:** finished runs with their final score

Until you complete the setup below, the game works fully **offline**: usernames are saved per device and the leaderboard shows the 5 sample BOT scores plus that device's own scores.

---

## One-time setup (≈10 minutes)

### 1. Create a Supabase project
1. Go to **supabase.com** → sign up (free) → **New project**.
2. Give it a name (e.g. `signal-noise`), set a database password (store it somewhere safe; you won't need it for the game), pick a region near your players, and click **Create**.

### 2. Create the database
1. In your project, open **SQL Editor → New query**.
2. Open `supabase-setup.sql` from this repo, copy **all** of it, paste it in, and click **Run**.
3. You should see *"Success. No rows returned"*. The script creates the tables, security rules, the 5 sample BOT scores and the functions the game calls. It's safe to run again later.

### 3. Connect the game
1. In Supabase open **Project Settings → API** (or **API Keys**) and copy:
   - the **Project URL** (looks like `https://abcdefghijkl.supabase.co`)
   - the **anon / publishable** key (a long public key)
2. *(Already done: `index.html` ships with your project's URL and publishable key filled in. Only change this if you move to a different Supabase project.)* Edit `index.html`, search for `const ONLINE`, and fill in both lines:
   ```js
   const ONLINE = {
     url: 'https://abcdefghijkl.supabase.co',
     key: 'eyJhbGciOi…   (or sb_publishable_…)',
   };
   ```
3. Commit. After GitHub Pages redeploys (1–2 minutes), first-time players see **New analyst / Log in**.

> **Is the key safe to publish?** Yes. That key is designed to be public. The setup script switches on Row Level Security and blocks every table, so the key can only call the game's `sn_*` functions, and those check each player's login token. **Never** put the `service_role` / secret key in the game.

---

## Updating an existing database

Each release that changes the backend comes with a `supabase-update-vX.Y.Z.sql` file. Run it once in **SQL Editor** (paste all of it → **Run**). Every update script is safe to run more than once.

- **v1.1.0** (`supabase-update-v1.1.0.sql`): adds player feedback (a `feedback` table, a private `feedback` storage bucket for screenshots/recordings, and the functions the game calls).
- **v1.0.0** (`supabase-update-v1.0.0.sql`): trims the sample bots to 5, returns the top 15 plus the player's own row, and accepts the original finish date of older careers being backfilled. Players' scores are untouched.

(`supabase-setup.sql` is always the full, current version, for brand-new projects.)

---

## Reviewing feedback & bug reports

Players send these from **Settings → Send feedback** (anonymous or logged in).

- **Read them:** Supabase → **Table Editor** → `feedback_inbox` (newest first, with attachment counts, device and version). The underlying table is `feedback`.
- **Attachments:** **Storage → feedback**. Each report has a folder named after its `id`; click a file to preview or download it.
- **Track progress:** in the `feedback` table, set `status` to `reviewing`, `planned`, `done` or `wontfix`, and use `owner_note` for your own notes. Players don't see these.
- **Limits:** up to 3 files (images or videos) and 25 MB per report, 5 reports per person per day, and 300 per day in total. The free plan includes 1 GB of storage. Delete old attachments from Storage when you're done with them (or run `delete from feedback where status in ('done','wontfix');` and delete the matching folders).
- **Game details** (`device` column) show the version, browser, screen size, whether it's installed, and the seed/shift the player was on, which is useful for reproducing bugs. No IP addresses are stored, only a one-way hash used for the daily limit.

---

## Releasing a new version

1. Make your changes to `index.html`.
2. In `index.html`, bump `const GAME_VERSION = '1.0.0'` (e.g. to `1.0.1`; use `MAJOR.MINOR.PATCH`).
3. In `version.json`, set the same `version`, today's `released` date, and a few short `notes` lines (they appear in the **What's new** popup).
4. Commit both files together. Once GitHub Pages redeploys (1–2 minutes), anyone opening an older copy sees the update banner.

If `version.json` is ahead of `index.html`, players get stuck seeing the banner, so always bump both.

---

## Home-screen install

`manifest.webmanifest` and the `icons/` folder let players add the game to their home screen. Both must stay next to `index.html`. `icons/logo.svg` is the source artwork; the PNGs are exported from it. There's no offline caching: the installed app loads the latest version from GitHub Pages each time.

---

## Day-to-day: moderating

Everything is in your Supabase dashboard → **Table Editor**.

| To… | Do this |
|---|---|
| Hide a cheated / offensive score | `runs` table → find the row → set **hidden** to `true` |
| Ban a player (hides all their scores, blocks login) | `players` table → set **banned** to `true` |
| Rename an offensive username | `players` table → edit **username** |
| Delete a player completely | `players` table → delete the row (their sessions, save and runs go with it) |
| Remove the sample BOT scores | SQL Editor → `delete from players where bot;` |
| See who's playing | `players` (accounts) · `runs` (scores) · `saves` (cloud saves, one per player) |

### Resetting a forgotten passcode
Players can't recover a passcode themselves. Once you've confirmed it's really them, in the **SQL Editor** run:
```sql
update players
   set pass_hash = crypt('1234', gen_salt('bf', 8)), failed_attempts = 0, locked_until = null
 where lower(username) = lower('TheirUsername');
```
Tell them the temporary passcode (`1234` here) and ask them to change it via **Profile → 🔑 Change passcode**.

### Lockouts
After **5 wrong passcodes**, an account is locked for **15 minutes**. To unlock early: `players` → clear **locked_until**.

---

## How scoring works (server-side)

The database recalculates every score itself (trigger `sn_runs_score`) using the same formula as the game, so a player can't just send a big number:

```
score = ( shifts×100 + prevented×40 + major_incidents_won×150 + tier×200
        + accuracy%×3 (after 10+ decisions) − SLA_breaches×5
        + shift-grade points (A 100 · B 70 · C 45 · D 20 · F 0)
        + 500 if retired )  × difficulty multiplier (0.6 / 1.0 / 1.3 / 1.6)
```

Leaderboards show each analyst's **best** run/career. Finished runs can't be changed afterwards.

### A note on cheating
The game runs in the player's browser, so a determined person could still send fake stats (they can't fake the score formula itself). Moderation is your safeguard: hide suspicious rows. Every run stores its **seed**, so you can replay the same run yourself to see whether the numbers are believable.

---

## Good to know

- **Free-tier pause:** Supabase pauses free projects after about a week with no activity. While paused, the game falls back to offline mode automatically. Restore it from the dashboard with one click. Any activity keeps it awake.
- **Tuning:** in `index.html`:
  - `GRADE_W`: the decisions / handoff weighting of the shift grade (default 60 / 40)
  - `GRADE_PTS`: points per shift grade
  - `DIFFS`: difficulty settings
  - `careerScore()`: the score formula. If you change it, update the trigger in `supabase-setup.sql` to match and re-run it.
- **`leaderboard.json` is no longer used.** You can delete it from the repo.
