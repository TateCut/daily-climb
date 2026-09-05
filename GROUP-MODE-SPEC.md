# 3·2·1 — Group mode spec

Turn the 2-player "Play a Friend" match into an **N-player group game**: one
invite link dropped in a family group chat, anyone who taps it joins the same
seeded session, and results are a **live leaderboard** that fills in as people
finish — never blocking on players who haven't shown up.

Status: spec agreed, not yet built. Supersedes the fixed `p1`/`p2` model from the
versus build. Key decisions are locked in §9.

---

## 1. Principles

1. **Never wait for a known headcount.** You can't know how many of the 10 people
   you texted will actually play. Nothing in the design may depend on that number.
2. **Finishing shows you standings immediately.** No "results are in" gate. The
   board is "everyone who's done so far" and it updates live.
3. **Joining stays open** until the game closes (optional deadline) — late taps
   can still play, just flagged.
4. **Same letters for everyone**, unchanged — `seed` + `mixSeed(seed, round)` is
   already player-count-independent.
5. **Solo is untouched** — no Firestore, no identity requirement, one-and-done.
6. **2-player is a group of 2** — same plumbing; the head-to-head "You win!"
   screen stays as a display special-case when exactly two people have finished.

---

## 2. The model

### Joining
- Host creates a game → gets a `?m=CODE` link (same as today) → shares it.
- Every tap of the link = a new **entrant**. Returning family members already
  have an identity (anon uid + saved name) so they skip the name prompt.
- The host is an entrant too (created on game-create, `done: false`).

### Playing
- Each entrant plays the 3 rounds whenever they want. Deterministic letters.
- On finish, the entrant's score + words are written to their own entrant doc.

### Seeing results — rolling leaderboard
- The instant you finish, you land on `#screen-leaderboard`: a ranked list of
  **everyone who has finished**, your row highlighted, plus a live footer
  *"3 finished · 2 still playing"*.
- It's a live `onSnapshot` — as others finish, rows animate in and ranks shift.
- You can reopen the game from **My Games** any time to see the current board.
- If you're the only finisher: *"You're first! Standings update as others play."*

### Closing
- At create time the host picks a close condition, **pre-set to "24h"**:
  - **24h** (default) / **48h** / **Pick a time** — sets a `closesAt` timestamp.
  - **No deadline** — board stays open forever, keeps accepting scores.
  - A game with a `closesAt` auto-archives from the main My Games list once it's
    Final; a no-deadline game auto-tucks into an "Older" group after ~7 days idle.
- After `closesAt` (checked client-side — no server needed):
  - The game shows **"Final"**. Ranks are locked.
  - People who never finished are dropped from the board (shown only as a count:
    *"4 didn't finish"*).
  - Someone opening the link after close can still play **"just for fun"** — they
    see where they'd have placed, not added to the official board
    (`late: true` on their entrant doc).
- The host (only) gets a **"Close now"** button on the leaderboard to end it early.

---

## 3. Data model

### Before (versus)
```
matches/{code} = {
  seed, difficulty, createdAt, updatedAt,
  p1: { name, done, total, roundWords },
  p2: { … } | null,
  players: [uid],
  uids: { p1, p2 },
}
```

### After (group)
```
matches/{code} = {
  seed, difficulty,
  createdAt, updatedAt,
  host: <uid>,
  closesAt: <timestamp> | null,
  status: "open" | "closed",          // "closed" set by host "Close now"; closesAt is the timed path
  entrantCount: <int>,                // denormalized, best-effort, for My-Games cards
  finishedCount: <int>,               // denormalized, best-effort
}

matches/{code}/entrants/{uid} = {
  name: <string>,
  joinedAt: <timestamp>,
  done: <bool>,
  total: <int>,
  roundWords: [ { words: [<string>] }, … ],   // same wrap trick as today
  finishedAt: <timestamp> | null,
  late: <bool>,                                // finished after close — unranked
}
```

Why a subcollection, not a `players` map on the doc:
- **Security** — a rule can say "you may only write `entrants/{yourUid}`". A map
  field can't be locked per-key.
- **Doc size** — 20 entrants × 3 rounds of words each would bloat one doc; still
  well under 1 MB, but the subcollection keeps writes small and independent
  (no lost updates when two people finish at once).
- **Reads** — the leaderboard is one `onSnapshot` on `entrants`, the game meta is
  one `onSnapshot` on the parent doc.

`entrantCount` / `finishedCount` are denormalized so a **My Games** card can say
"4 done" without subscribing to every game's subcollection. Updated with
`increment(1)` on join / finish; treated as approximate (a missed increment just
makes a card slightly stale, never breaks the leaderboard which counts real docs).

---

## 4. Adapter (`window.MatchDB`) changes

New / changed methods:

| method | change |
|---|---|
| `createMatch(name, difficulty, closeOption)` | writes the new parent shape (`host`, `closesAt`, `status:"open"`), then creates `entrants/{uid}` for the host with `done:false`. Returns `{ code, seed }`. |
| `joinMatch(code, name)` | if `entrants/{uid}` exists → return it (re-open, no-op). Else create it (`done:false`, `late` = now past `closesAt`), `increment(entrantCount)`. Returns the game meta. |
| `submitResult(code, total, roundWords)` | writes to `entrants/{uid}` (`done:true`, `total`, `roundWords` wrapped, `finishedAt`), `increment(finishedCount)`. No more `slot` arg. |
| `watchEntrants(code, cb)` | **new** — `onSnapshot(collection(matches/{code}/entrants))`, cb gets `[{ uid, …entrant }]`. Returns unsubscribe. |
| `watchMatchMeta(code, cb)` | **new** — `onSnapshot(doc(matches/{code}))`, for `closesAt` / `status`. (Can fold into `watch`.) |
| `closeMatch(code)` | **new** — host sets `status:"closed"`. Rule checks `request.auth.uid == resource.data.host`. |
| `watchMyMatches(cb)` | unchanged query (`where("players"…)`) **but** `players` is gone — switch to a `collectionGroup("entrants")` query `where(uid==)` **or** keep a `playerUids` array on the parent updated via `arrayUnion` on join. Keep the array — collectionGroup needs its own index and rules. |

Keep a **read-compat shim** for the handful of existing `p1`/`p2` docs: if a match
doc has a `p1` field, synthesize an entrants array from `p1`/`p2` + `uids` on
read. No write migration — old matches just resolve on new clients; don't bother
converting them.

---

## 5. Screens & flow

### New: `#screen-leaderboard`
- Title: game difficulty + status (`Open` / `Closes in 3h` / `Final`).
- Ranked rows: `#`, name, score. Your row accented. Tap a row → that person's
  per-round words (reuse `renderRoundsBlock`).
- Footer: *"3 finished · 2 still playing"* (live), or *"4 didn't finish"* once Final.
- Buttons: `← My games`; host-only `Close now` while open.
- **Exactly-2 special case:** if the game has 2 entrants and both are done, show
  the existing `#screen-vs-reveal` head-to-head instead (crown, "You win!").
  3+ → always the leaderboard.

### Changed: after you finish (`afterAllRounds` → versus path)
- `submitResult(...)` then `show("leaderboard")` + `watchEntrants`.
- Drop `#screen-vs-waiting` as the terminal state — there's no "waiting", you go
  straight to the (possibly 1-row) board. Keep the screen only for the 2-player
  "waiting for the one other person" moment, or retire it.

### Changed: create flow (`#screen-vs-create`)
- Add a close-condition control under the difficulty picker, **default 24h**:
  `(•) 24h  ( ) 48h  ( ) Pick a time  ( ) No deadline`
- Everything else the same.

### Changed: join flow (`#screen-vs-join`)
- Lede: *"{host} started a family game of 3·2·1"* (drop "challenged you to").
- Show current turnout: *"5 playing so far"*.
- If past `closesAt`: *"This game has closed — you can still play for fun."*

### Changed: My Games cards (`matchStatus`)
- `turn`: "Family game · your turn" (you haven't finished)
- `waiting` → rename concept to **live**: "Family game · you're 2nd of 4"
- `done`/Final: "Family game · finished 2nd of 6"
- 2-player games keep today's "vs Sam · You won 12–9".
- Card sub-line count comes from `finishedCount` / `entrantCount` on the parent.

### Unchanged
- Solo entirely. Identity / name screen. The game itself (rounds, tiles, timer,
  seeded letter generation).

---

## 6. Firestore rules

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    match /players/{uid} {
      allow read: if true;
      allow write: if request.auth != null && request.auth.uid == uid;
    }

    match /matches/{code} {
      allow read: if true;
      allow create: if request.auth != null
                    && request.resource.data.host == request.auth.uid;
      // updates: host may change status; anyone signed-in may bump the
      // denormalized counters / updatedAt. Keep it loose for v1:
      allow update: if request.auth != null;
      allow delete: if false;

      match /entrants/{uid} {
        allow read: if true;
        allow create, update: if request.auth != null
                              && request.auth.uid == uid;
        allow delete: if false;
      }
    }
  }
}
```

(Tightening the parent `update` rule to field-level checks — host-only `status`,
counters only `increment` — is a nice-to-have, not v1.)

---

## 7. Ranking & edge cases

- **Order:** `total` desc, then `finishedAt` asc (ties broken by who finished
  first — rewards speed, consistent with the carry-over timer). No visible
  co-ranks; every row gets a distinct number.
- **Only one finisher:** board shows 1 row + "standings update as others play".
- **You open the game without having finished:** show the live board of others +
  a "Finish your game to join the board" prompt + Resume button (runs your rounds).
- **Closed mid-play:** your `submitResult` still succeeds; entrant flagged
  `late: true`; board lists late finishers in a separate "After the deadline"
  group, unranked.
- **Nobody else ever plays:** you're alone on the board forever — fine, it reads
  "1st of 1".
- **Duplicate names ("Mom" ×2):** allowed; ignore for v1. Could append a last
  initial later if it bites.
- **Host abandons:** no problem — the timed `closesAt` path needs no host. The
  "Close now" button is just a convenience.

---

## 8. Build phases

Each phase ships and is testable on its own.

**Phase A — schema + adapter (no visible change). ✅ SHIPPED (13a76c8).**
New parent shape + `entrants` subcollection + rules. Adapter rewritten to the
new methods with the `p1`/`p2` read-compat shim. 2-player still works end to end,
just routed through `entrants`. Verified on real Firestore: create, join from
two more origins, 2-player head-to-head reveal, 3-player holding screen with
live rank. Phase A shortcuts to revisit in B/C: 3+ holding screen is text-only
(no leaderboard); tie-break is by uid order not `finishedAt`; legacy `p1`/`p2`
matches drop off My Games; "closed, didn't play" wording is rough.

**Phase B — leaderboard screen. ✅ SHIPPED (1282b1e).**
`#screen-leaderboard`, live `watchEntrants`, ranking (total desc, `finishedAt`
asc), your row accented, "playing…" rows, tap-to-expand per-round words, host
two-tap "Close game now" + invite link, `closesInText()` status line. 2-player
still routes to the head-to-head reveal / simple wait; self-heals if a 2-player
game gains a 3rd player mid-wait. Verified on real Firestore.

**Phase C — open join + close conditions. ✅ SHIPPED (492ac4b).**
Create-flow "Closes" picker (24h default / 48h / 1w / none — "pick a time"
dropped, note if wanted). `closesAt`/`status` → closed state; join screen
"play for fun"; `lateUids` on the parent, late entrants excluded from roster
+ ranks, shown in an "After the deadline" leaderboard group. `doneUids`
finish-order array for stable tie-ranking. Head-to-head reveal keeps its
watches alive (2→3 flip). Verified on real Firestore.

**Phase D — My Games polish.**
Group-aware `matchStatus`, "you're 2nd of 4" cards, turnout counts on the join
screen, auto-archive of Final / idle games into an "Older" group. Test the card
copy across all states.

**Later / out of scope:** push notification triggers (step 3) fire naturally on
`entrants` create ("Sam joined") and finish ("Sam scored 11") — wire when step 3
lands. Per-round live progress ("Mom is on round 2"). Rematch-with-same-group.

---

## 9. Decisions locked

1. **Close default: 24h.** New games pre-select a 24h `closesAt` (host can pick
   48h, a custom time, or No deadline). Timed games auto-archive from the main
   My Games list when Final; no-deadline games tuck into "Older" after ~7d idle.
2. **2-player keeps the head-to-head reveal.** Exactly 2 entrants, both done →
   `#screen-vs-reveal` (crown, "You win!"). 3+ → `#screen-leaderboard`.
3. **`#screen-vs-waiting`** stays *only* for the 2-player "waiting for the one
   other person" moment. For 3+ the leaderboard (even at 1 row) is the terminal
   screen — no waiting state.
4. **My Games query:** keep a `playerUids` array on the parent doc
   (`arrayUnion` on join) — no new composite index, `watchMyMatches` barely
   changes. Not a `collectionGroup` query.
5. **Naming:** code stays `match*`; UI strings say "game" ("family game",
   "start a game", "this game has closed").
