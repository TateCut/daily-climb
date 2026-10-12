# Daily Climb

A daily word-ladder game: three themed climbs a day, from a 4-letter word up to
peaks of 6, 7 and 8 letters, one letter at a time, with 3+ forks in the trail a day
(steps where an everyday word and a theme word fit the same letters). Play at **https://thedailyclimb.com**.

© 2026 Tate Cutcliffe. All rights reserved.

## What's here

- `index.html`: the whole game (HTML, CSS and JS in one file, no build step)
- `sw.js`, `manifest.webmanifest`, `icon-*.png`: the installable web app
- `words.js` (ENABLE word list), `freq.js` (everyday-word ranking), `climbs.js`
  (Adventure Mode's 746 climbs), `daily-calendar.js` (the themed daily)
- `themes.txt`, `climb-blocklist.txt`, `daily-pool.js`: inputs for new climbs
- `gen-*.pl`, `verify-*.pl`: tools that build and check climbs. The daily
  calendar is built by `gen-calendar-678.pl` (FROM=<first day to rebuild>; earlier days are
  kept as they are) and checked by `verify-calendar.pl`. Don't re-run the old
  `gen-calendar.pl` over it.
- `firebase-config.js`: the public Firebase web config (leaderboards, profiles)

The reminder and nightly stats jobs live in the portfolio repo
(`TateCut/game-portfolio`, `tools/` + `.github/workflows/`).
