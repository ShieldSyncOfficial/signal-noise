# Maintainer guide: online accounts & live leaderboards

This guide is for the game owner (**shieldsyncofficial**). Players don't need it.

SIGNAL//NOISE uses **Supabase** (free tier) for:

- **Accounts:** unique usernames + 4-digit passcodes (case-insensitive, so "NightHawk" and "nighthawk" are the same name)
- **Cloud saves:** log in on any device and your whole profile and run in progress come with you
- **Live leaderboards:**
  - **Runs:** every run's total, posted automatically each time a player clocks out of a shift (unfinished runs included, marked LIVE)
  - **Careers:** finished runs with their final score

Until you complete the setup below, the game works fully **offline**: usernames are saved per device and the leaderboard shows the 10 sample BOT scores plus that device's own scores.

---

## One-time setup (≈10 minutes)

### 1. Create a Supabase project
1. Go to **supabase.com** → sign up (free) → **New project**.
2. Give it a name (e.g. `signal-noise`), set a database password (store it somewhere safe; you won't need it for the game), pick a region near your players, and click **Create**.

### 2. Create the database
1. In your project, open **SQL Editor → New query**.
2. Open `supabase-setup.sql` from this repo, copy **all** of it, paste it in, and click **Run**.
3. You should see *"Success. No rows returned"*. The script creates the tables, security rules, the 10 sample BOT scores and the functions the game calls. It's safe to run again later.

### 3. Connect the game
1. In Supabase open **Project Settings → API** (or **API Keys**) and copy:
   - the **Project URL** (looks like `https://abcdefghijkl.supabase.co`)
   - the **anon / publishable** key (a long public key)
2. Edit `index.html` on GitHub, search for `const ONLINE`, and fill in both lines:
   ```js
   const ONLINE = {
     url: 'https://abcdefghijkl.supabase.co',
     key: 'eyJhbGciOi…   (or sb_publishable_…)',
   };
   ```
3. Commit. After GitHub Pages redeploys (1–2 minutes), first-time players see **New analyst / Log in**.

> **Is the key safe to publish?** Yes. That key is designed to be public. The setup script switches on Row Level Security and blocks every table, so the key can only call the game's `sn_*` functions, and those check each player's login token. **Never** put the `service_role` / secret key in the game.

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
