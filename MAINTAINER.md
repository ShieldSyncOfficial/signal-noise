# Maintainer guide: SIGNAL//NOISE leaderboard

This guide is for the repo owner (**shieldsyncofficial**). Players don't need it.

## How the leaderboard works

| Piece | Where | Purpose |
|---|---|---|
| `leaderboard.json` | repo root | The **full** official board (every approved career). The game downloads it from GitHub Pages when online. |
| Embedded block in `index.html` | between `<!-- LEADERBOARD:BEGIN -->` and `<!-- LEADERBOARD:END -->` | The **top 25**, built into the page so the board still works offline and when the file is opened locally. |
| `reviewedAt` | inside both | Your review timestamp. Players see it as *"Official board last reviewed: …"* in **their own timezone**. |

The game always shows whichever copy has the newest `reviewedAt`. Each player's own careers are merged in **live** as *UNOFFICIAL · PENDING REVIEW* until you publish them.

## Settings (top of the script in `index.html`)

Search for `LB_CONFIG`:

```js
const LB_CONFIG = {
  repo: 'shieldsyncofficial/signal-noise',
  jsonUrl: 'https://shieldsyncofficial.github.io/signal-noise/leaderboard.json',
  anonFormUrl: '',   // ← paste your Google Form pre-filled link here (see below)
  embeddedTop: 25,
};
```

## How players submit

1. **🐙 Submit via GitHub**: opens a pre-filled issue on this repo. Requires **Issues to be enabled**: *Settings → General → Features → Issues*. The player's GitHub username is public on the issue.
2. **🕶 Submit anonymously**: appears once `anonFormUrl` is set. Opens your Google Form with the code already filled in. **No email or account on either side; your contact info stays private.**
3. **⧉ Copy code / ⇩ Download file**: a fallback; they send you the text however you've told them to.

A submission code looks like `SNLB1.eyJpZCI6…​.k3j9x2` and contains only the callsign, a random profile tag, difficulty and career stats.

## Setting up the anonymous form (≈5 minutes)

1. Go to **forms.google.com** and create a blank form, e.g. "SIGNAL//NOISE score submission".
2. Add **one** question, type **Paragraph**, titled "Submission code". Make it required.
3. Open **Settings → Responses**:
   - **Collect email addresses → Do not collect**
   - **Limit to 1 response → Off** (this would force sign-in)
   - Leave "Allow response editing" off.
4. Open **⋮ (More) → Get pre-filled link**, type `{CODE}` as the answer, and click **Get link → Copy link**.
5. The link looks like
   `https://docs.google.com/forms/d/e/1FAIpQL…/viewform?usp=pp_url&entry.123456789=%7BCODE%7D`
   Replace `%7BCODE%7D` at the end with `{CODE}` and paste it into `anonFormUrl`:
   ```js
   anonFormUrl: 'https://docs.google.com/forms/d/e/1FAIpQL…/viewform?usp=pp_url&entry.123456789={CODE}',
   ```
6. Commit `index.html`. The **🕶 Submit anonymously** button now appears on the leaderboard.

Responses arrive in the form's **Responses** tab (or a linked Google Sheet). Players never see your email, and you never see theirs.

## Reviewing & publishing (each time)

1. Open your live game → **🏆 Leaderboard → 🔧 Owner tools**.
2. Click **⟳ Refresh from GitHub** so you start from the latest published board.
3. Paste everything containing submission codes into the box: whole GitHub issue texts, a copied column from the form responses sheet, or the contents of files players sent. Click **Find codes**, or use **Add files…**.
4. Review each entry. The tool re-calculates scores and flags corrupted or edited codes, implausible stats, future dates and duplicates. Tick what you approve. In *Existing official entries* you can untick entries to remove them.
5. Click **Build updated board**, then:
   - **⇩ leaderboard.json** → upload it to the repo root, replacing the old one.
   - **⧉ Copy index.html block** → on GitHub, edit `index.html`, select everything from `<!-- LEADERBOARD:BEGIN` through `<!-- LEADERBOARD:END -->`, paste over it, and commit.
   After you click Build, *your* leaderboard immediately shows the new board and review time, labelled **"Your built preview · not published yet"**. Only your browser sees this preview; it survives reloads and clears itself once GitHub serves the new board. Use **✕ Discard preview** in Owner tools to throw it away.
6. GitHub Pages redeploys in 1–2 minutes. Every player then sees the new board and the new *last reviewed* time, converted to their local timezone.
7. Close the approved GitHub issues (optional).

### Sample (bot) entries

The board ships with 10 sample entries named `BOT-…` (ids `bot01`–`bot10`), spread across all four difficulties and tagged **BOT** in the game, so the board isn't empty at launch. To remove them, open **Owner tools**, untick them under *Existing official entries*, then **Build** and publish as usual.

### A note on cheating

The game runs entirely in the player's browser, so a determined person could fake a score. The codes catch accidents and casual edits, but **your review is the real safeguard**. Use judgement on extreme scores. Every entry includes its **seed**, so you can replay the same career yourself to see whether the numbers are believable.
