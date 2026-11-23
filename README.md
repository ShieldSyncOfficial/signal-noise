# SIGNAL//NOISE — A SOC Analyst Roguelike

> Survive the queue. Protect the org. Don't burn out.

**SIGNAL//NOISE** is a browser roguelike where you play a Security Operations Center (SOC) analyst at a 24/7/365 SOC. Each run is a career. Triage alerts, investigate logs, write shift handoffs, and climb from **Tier 1 Analyst** to **SOC Lead** before stress, a ruined reputation, or a catastrophic breach ends it all.

The whole game is **one self-contained HTML file**: no libraries and no build step. It runs offline. Online accounts, cloud saves and live leaderboards are optional and use a free Supabase backend.

![Day shift at the analyst's desk](screenshots/day-shift.png)

---

## ▶ Play

- **Locally:** download `index.html` and double-click it. It works in any modern desktop browser (Chrome, Firefox, Edge).
- **Online:** if GitHub Pages is enabled for this repo, play at
  `https://<your-username>.github.io/<repo-name>/`

**First launch:** create an analyst account (a unique **username** + **4-digit passcode**) or **log in** with an existing one, then go through a short, required **walkthrough** (about 5 minutes) that explains everything in plain language, with hands-on practice, before your first career. You can replay it any time from **🎓 Tutorial** on the main menu. **? How to Play** is the quick reference.

![Walkthrough practice page](screenshots/walkthrough.png)

The whole interface scales to fit whatever window it's in, from a small laptop window to a 4K monitor, so nothing gets cut off. Text size can be adjusted in **Settings**.

### 📱 On phones & tablets
Open the GitHub Pages link in your phone's browser. On narrow or short screens the game switches to a **touch layout**: one screen at a time, with a bottom tab bar for **Queue**, **Case** (investigation) and **Comms**, plus a ☕ coffee button. Badges show open alerts and unread messages, and tapping an alert opens it straight in Case. Portrait and landscape both work.

For a full-screen, app-like experience, use your browser's **Share → Add to Home Screen** (iOS) or **⋮ → Add to Home screen** (Android), or tap **Fullscreen** on the main menu where it's supported.

<p>
  <img src="screenshots/mobile-queue.png" width="260" alt="Mobile alert queue">
  <img src="screenshots/mobile-case.png" width="260" alt="Mobile investigation view">
</p>

---

## 🎮 How it plays

You sit at a first-person desk with three curved monitors:

| Monitor | What it does |
|---|---|
| **1 — SIEM Queue** | Incoming alerts with severity, source, timestamp and a live SLA countdown |
| **2 — Investigation** | Logs, IP lookup, user lookup, process trees, email headers |
| **3 — Comms** | Team chat, tickets, handoff notes, and the incident bridge during major incidents |

Behind the monitors, a city window tracks the shift clock, from sunrise through daylight to a neon skyline at night.

### The core loop
1. **Triage** an alert (free).
2. **Investigate**: run queries and inspect lines. Each costs in-game time and energy. Red lines are malicious indicators; green lines are benign context such as an approved change.
3. **Decide**: close it as a False Positive or Benign True Positive, escalate to Tier 2/IR, or contain it yourself (block IP, isolate host, disable account). Containment has to match the threat.
4. **Live with it.** Feedback arrives later, like the real job. True positives you miss come back on later shifts as worse incidents: a missed beacon on Tuesday night becomes ransomware on Thursday.

### Shifts & handoffs
- **Day (06:00–18:00):** more users, phishing reports, meetings, manager walk-bys.
- **Night (18:00–06:00):** skeleton crew, automated attacks, heavier fatigue. Coffee hits harder and crashes harder.
- **Incoming handoff (05:45 / 17:45):** read the outgoing analyst's notes. Some are sloppy and leave things out, and asking a follow-up question can surface what they forgot.
- **Outgoing handoff:** choose which open tickets, IOCs and warnings to pass on. You get a grade from A to F, and omissions come back as *"you didn't tell us about this."*

![Incoming shift handoff](screenshots/handoff.png)

### Shift grades
Every shift ends with three grades:

| Grade | What it measures |
|---|---|
| **Decisions** | Accuracy (correct calls ÷ calls), minus 8 per SLA breach, 12 per real attack closed as harmless, and 2 per alert left in the queue beyond the first two |
| **Handoff** | Including every open ticket, real IOC and important system note, and leaving out junk |
| **Shift grade** | **60% Decisions + 40% Handoff** (A ≥ 90 · B ≥ 75 · C ≥ 60 · D ≥ 40) |

The shift report breaks down exactly what earned or cost points, and the shift grade adds points to your run score. **📋 Shift history** (pause menu, days-off screen and each past run in your profile) lists every shift's grades.

![Shift report](screenshots/shift-report.png)

### Resources
- **Energy** drains over the shift. Coffee and breaks restore it.
- **Caffeine** boosts energy now, raises stress, and causes a crash later.
- **Stress** rises with backlog, mistakes and night shifts.
- **Reputation** rises with accurate calls and good handoffs.

### Shift cards (run modifiers)
Three times per shift (around the 3-, 6- and 9-hour marks), you reach a **checkpoint** and pick 1 of 3 randomized cards. Each card lasts for the rest of that career:

| Type | What it does |
|---|---|
| 🟢 **Boon** | A pure buff, e.g. *Saved Searches* (faster queries) or *Noise-Cancelling Headphones* (less stress) |
| 🟠 **Trade-off** | An upside with a cost, e.g. *Cold Brew Drip* (stronger coffee, harder crashes) |
| 🟣 **Curse** | Makes the run harder, e.g. *Understaffed* or *Tightened SLAs*, but pays Career Points now and **Legacy Points when the run ends** |

Boons get rarer and curses more common as you climb tiers. Press `1`–`3` to pick, or skip the checkpoint. Press `C` (or click the 🃏 chip in the HUD) to review your active cards.

![Shift checkpoint card pick](screenshots/shift-cards.png)

### Major incidents
Every 5th shift, a major incident (ransomware outbreak, supply-chain compromise, or zero-day exploitation) opens a **timed incident bridge**. Complete at least 3 of 4 objectives before time runs out.

![Major incident bridge](screenshots/incident-bridge.png)

### Run endings
| Ending | Cause |
|---|---|
| 🔥 **Burnout** | Stress hits 100 |
| 📉 **Terminated** | Reputation hits 0 |
| 💥 **Catastrophic Breach** | A critical incident is missed, left open too long, dropped from a handoff, or a bridge fails |
| 👑 **Retired a Legend** | Reach SOC Lead and retire on your own terms |

### Progression
- **Within a run:** on days off, spend Career Points on rest, training and (fictional) certifications. Promotions need shifts survived, reputation, and the right cert.
- **Across runs:** earn Legacy Points (from finished careers and first-time achievements) to unlock permanent perks and tools: *Grep Ninja*, *Barista-Grade Coffee*, *Tuned Detection Rules*, *Mentor on Call*, *Threat Intel Feed*, *SOAR Playbooks*, and higher starting tiers.

---

## ⌨ Controls

| Key | Action |
|---|---|
| `J` / `K` | Move through the alert queue |
| `1`–`5` | Evidence tabs (Logs, IP, User, Process, Email) |
| `F` | Close as False Positive |
| `B` | Close as Benign True Positive |
| `E` | Escalate to Tier 2 / IR |
| `P` / `I` / `D` | Contain: Block IP / Isolate Host / Disable Account |
| `Q` / `R` | Sip coffee / refill mug |
| `Space` | Pause |
| `T` | Fast-forward ×3 |
| `1`–`3` | Pick a card at a shift checkpoint |
| `C` | View active shift cards |
| `M` | Toggle sound |
| `L` | Desk lamp |
| `Esc` | Menu |

Everything is also playable with the mouse, or with touch on phones and tablets (no keyboard needed).

---

## 🎚 Difficulty

Choose a difficulty for each career. It's recorded in your run history and profile and applied to your leaderboard score:

| Difficulty | Who it's for | What changes | Leaderboard |
|---|---|---|---|
| 🌱 **Beginner** | Anyone, no tech background needed | 30% fewer alerts, 50% longer SLAs, gentler stress and energy, fewer curses, longer major-incident timers, and **5 hints per shift** from your mentor | ×0.6 |
| 🛡 **Standard** | The intended experience | Baseline | ×1.0 |
| ⚔ **Veteran** | Experienced players | 20% more alerts, tighter SLAs, more real attacks, subtler evidence | ×1.3 |
| ☠ **Advanced** | Masochists | 40% more alerts, short SLAs, stealthy attackers, a major incident every 4th shift | ×1.6 |

---

## 🏆 Leaderboards (live)

With an online account, your scores post **automatically**. There's no submitting.

- **🏃 Runs (live):** every run, including unfinished ones (marked **● LIVE RUN**). Your run's total is posted each time you **clock out of a shift**.
- **🏆 Careers:** finished runs with their final score.
- Each board shows every analyst's **best** entry, filterable by difficulty, and when the leaderboard last changed (in your local timezone).
- The leaderboard refreshes **every time you open it**, every 30 seconds while it's open, and whenever you press **⟳ Refresh**.
- **Score** = shifts survived, incidents prevented, major incidents contained, tier, accuracy, shift grades and a retirement bonus, minus SLA breaches, times the difficulty multiplier. The server calculates it.

![Leaderboard](screenshots/leaderboard.png)

*Maintainers: see [MAINTAINER.md](MAINTAINER.md) to set up the backend and moderate scores.*

---
## 🔐 Account & cloud saves

- **New analyst:** choose a unique username (case-insensitive, 2–16 characters) and a 4-digit passcode.
- **Log in** on any browser, computer or phone with the same username + passcode, and your whole profile *and* the run in progress come with you.
- Progress saves to the cloud automatically (after each shift, at the end of a run, and about once a minute while playing). If you're offline, uploads wait and go through when you reconnect.
- **Profile → Log out** saves to the cloud and clears the device, so someone else can use it. **Change passcode** is there too. Forgot your passcode? Ask the game owner to reset it.
- After 5 wrong passcodes an account locks for 15 minutes. A 4-digit passcode is light protection, so don't reuse a real PIN.
- **⇩ Save Profile / ⇪ Load Profile** still download and restore a backup file (drag and drop works too). Files never contain your login.

---
## 👤 Profile, achievements & run history

Open **👤 Profile** from the main menu or pause menu:

- **Overview:** your account (sync status, change passcode, log out) and lifetime stats: careers finished, shifts survived, alerts handled, accuracy, incidents prevented, major incidents contained, cards taken, Legacy Points earned, your best career, and how your careers ended.
- **Achievements:** 34 achievements across five categories (Career, Skill, Incidents, Cards, Lifetime), each with its unlock date and LP reward. Lifetime achievements show progress bars.
- **Run history:** your last 100 careers, each with ending, **difficulty**, score, date, seed, shifts, tier, accuracy and LP. Open one to see its full breakdown, including a **shift-by-shift history** with every shift's grades, certifications, cards and achievements. You can replay its seed or delete it.

![Profile overview](screenshots/profile.png)

---

## 🎲 Seeds

Every run uses a seeded RNG. The seed appears on the sticky note on your desk, in the run summary and in your run history, where you can replay it with one tap. Share it, and anyone entering the same seed gets the same career: the same alerts, handoffs and events.

---

## ⚙ Settings

- Clock speed (1–3 in-game minutes per real second)
- Sound effects, synthesized with the Web Audio API and **muted by default**
- Reduced motion
- CRT scanlines on/off
- Text & interface size (Normal / Large / Extra large)

Progress is saved in `localStorage` and the game pauses itself when you switch tabs. If storage is unavailable (e.g., some private-browsing modes), the game still runs, and a saved profile file keeps your progress.

---

## 🛠 Tech

- One HTML file with inline CSS and JavaScript
- Visuals built from CSS, inline SVG and `<canvas>`. No images or fonts are loaded
- Audio generated with the Web Audio API
- No dependencies and no build step. Online features talk to Supabase's REST API directly (no SDK); without it, everything works offline.
- `supabase-setup.sql` creates the backend: tables, security rules and server-side functions.

### Code layout (inside `index.html`)
The script is organized into numbered, commented sections:

1. Utilities & seeded RNG
2. Persistence (`localStorage`, wrapped in try/catch)
3. Static game data (tiers, certs, unlocks, achievements)
4. Organisation & evidence helpers
5. Alert generators (phishing, password spray, impossible travel, C2 beacon, PowerShell, exfil, privesc, insider, DDoS, scanner noise, false positives)
6–12. Game state, shift generation, simulation tick, decisions, resources, handoffs, run end
13. Random desk events
14. Boss encounters (incident bridge) and mid-shift cards
15. Tutorial
16. Audio
17–20. Rendering, screens, profile & run history, save/load, fit-to-window scaling, mobile touch layout, input and the main loop

### Tuning
To make the game easier or harder, start with these:
- `judge()`: reputation and points for each decision
- `SLA_BASE`: SLA minutes per severity
- `resources()`: energy drain and stress accumulation
- `TYPE_W`: the mix of alert types on day vs. night shifts
- `DIFFS`: difficulty settings and leaderboard multipliers
- `careerScore()`: the leaderboard scoring formula (mirrored by the server trigger)
- `GRADE_W` / `GRADE_PTS`: shift-grade weighting and points
- `ONLINE`: your Supabase URL and public key
- `CARDS`: shift card effects, stack limits and curse payouts
- `ACH`: achievements, their LP rewards and lifetime progress goals

---

## ⚠ Disclaimer

All companies, people, domains, IP addresses and certifications are fictional. Any resemblance to real organizations is coincidental. The game is meant to be fun and loosely educational about SOC work. It is not a training course.
