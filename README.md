# Daily Climb

A daily word-ladder game: three themed climbs a day, from a 4-letter word up to
peaks of 7–11 letters, one letter at a time. Play at **https://thedailyclimb.com**.

© 2026 Tate Cutcliffe. All rights reserved.

## What's here

- `index.html`: the whole game (HTML, CSS and JS in one file, no build step)
- `sw.js`, `manifest.webmanifest`, `icon-*.png`: the installable web app
- `words.js` (ENABLE word list), `freq.js` (everyday-word ranking), `climbs.js`
  (Adventure Mode's 746 climbs), `daily-calendar.js` (the themed daily)
- `themes.txt`, `climb-blocklist.txt`, `daily-pool.js`: inputs for new climbs
- `gen-*.pl`, `verify-seeds.pl`: tools that build and check climbs. The live
  calendar is patched in place: don't re-run `gen-calendar.pl` over it.
- `firebase-config.js`: the public Firebase web config (leaderboards, profiles)

The reminder and nightly stats jobs live in the portfolio repo
(`TateCut/game-portfolio`, `tools/` + `.github/workflows/`).
