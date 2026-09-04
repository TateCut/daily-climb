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
window.THREE21_FIREBASE_CONFIG = {
  apiKey: "AIzaSyDI0tORlO2mVonwaezbgTydO37sziB_uhM",
  authDomain: "project-4425863557740357535.firebaseapp.com",
  projectId: "project-4425863557740357535",
  storageBucket: "project-4425863557740357535.firebasestorage.app",
  messagingSenderId: "264476826239",
  appId: "1:264476826239:web:570e50b08aaf6b60d6fd4a",
};
