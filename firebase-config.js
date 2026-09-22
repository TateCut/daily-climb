// Firebase project config for 3-2-1's "Play a Friend" versus mode.
//
// To enable versus mode:
//   1. Create a free project at https://console.firebase.google.com
//   2. Build > Firestore Database > Create database (start in production mode
//      is fine — the security rules below open up just the `matches`
//      collection).
//   3. Project settings (gear icon) > General > "Your apps" > add a Web app.
//      Copy the `firebaseConfig` object it gives you into THREE21_FIREBASE_CONFIG
//      below.
//   4. Firestore Database > Rules, paste:
//        rules_version = '2';
//        service cloud.firestore {
//          match /databases/{database}/documents {
//            match /matches/{code} {
//              allow read, write: if true;
//            }
//          }
//        }
//      (Wide open by design — there's no login. A match code is effectively
//      the shared "password" for that game, same trust model as a Wordle
//      share link. Don't put anything sensitive in this collection.)
//
// Until this is filled in, "Play a Friend" stays disabled and solo play is
// unaffected.
//
// To enable the analytics dashboard (unique/daily users, engagement time,
// Daily Climb funnel — see index.html's "daily_start"/"daily_round_complete"/
// "daily_finish" events):
//   1. console.firebase.google.com > this project > gear icon (top left) >
//      Project settings > Integrations tab > Google Analytics > Enable.
//      (Creates or links a GA4 property — a Google login you already have.)
//   2. Project settings > General tab > "Your apps" > the web app > find
//      "measurementId" (looks like "G-XXXXXXXXXX") in its config snippet.
//   3. Paste it as `measurementId` below.
//   4. View data at analytics.google.com (pick the linked property) — NOT
//      part of this site, players never see it. Realtime/Engagement give you
//      unique + daily users and time played for free; Explore > Funnel
//      exploration on daily_start -> daily_finish (or the per-round events)
//      answers "who started a Daily Climb and didn't finish."
window.THREE21_FIREBASE_CONFIG = {
  apiKey: "AIzaSyDI0tORlO2mVonwaezbgTydO37sziB_uhM",
  authDomain: "project-4425863557740357535.firebaseapp.com",
  projectId: "project-4425863557740357535",
  storageBucket: "project-4425863557740357535.firebasestorage.app",
  messagingSenderId: "264476826239",
  appId: "1:264476826239:web:570e50b08aaf6b60d6fd4a",
  measurementId: "G-R11NF60DHM",
};
