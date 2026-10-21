# App Store and Play review: what to prepare

This is for you, not for the app. Nothing here is shipped to players.

## 1. Reviewer access (Apple 2.1, Google "app access")

Reviewers must be able to reach every feature without help.

**Demo mode needs nothing.** "Play as guest" on the first screen opens the full app with 10,000 free demo credits. Every game works there.

**Live (real money) mode** needs a funded account, because the reviewer cannot be expected to pay. Do it honestly, with no hidden code or fake-money switch in the app:

1. Once payments are live, create a normal account (for example `review@yourdomain.com`) and deposit a small real amount into it yourself.
2. Put that email and password in App Store Connect, under App Review Information > Sign-in required.
3. Keep the account funded while the review runs, and top it up if the reviewer plays it down.
4. Do NOT enable the test-payments mode on the production server for this. It would let anyone "deposit" without paying.

If a reviewer in a region where real-money play is not allowed opens live mode, they should see the "not available here" message. Say that in the notes so it does not look like a bug.

## 2. Text for the "Notes" box in App Store Connect

> REV GAMES is a casino-style game app with two modes.
> Demo mode: tap "Play as guest" on the first screen. It uses free demo credits that have no cash value, and every game is playable.
> Live mode: sign in with the account in the fields above. It is funded with real money, so wins and losses are real. Switch modes from the balance at the top of the lobby.
> Sign in with Apple, Google, email, phone and guest are all offered.
> All results are decided on our server and every round can be checked under Provably fair (the shield icon in each game).
> Players must be 18 or older. Terms of Service and Privacy Policy are linked on the sign-in screens and in Settings > Legal and policies.
> Our gaming licence number is: <FILL IN>.

## 3. Sign in with Apple: steps only you can do

The app code and the iOS entitlement file are in place. You still need to:

1. Apple Developer > Identifiers > your app ID > turn on **Sign in with Apple**.
2. Firebase console > Authentication > Sign-in method > turn on **Apple**.
3. Open `ios/Runner.xcworkspace` in Xcode once, pick your paid team under Signing & Capabilities, and confirm "Sign in with Apple" is listed. (A free personal team cannot sign this capability. If you are still testing on one, remove the line `CODE_SIGN_ENTITLEMENTS` for now.)
4. Account deletion: Apple also expects the Apple sign-in token to be revoked when someone deletes their account (guideline 5.1.1(v)). Deleting the account already removes the Firebase user. Revoking the Apple token needs the authorization code at deletion time, which is a small follow-up once the rest is working.

## 4. Before you submit

- Change the bundle id `com.example.revGameMvp` (iOS) and the Android application id to your own. Then re-download `GoogleService-Info.plist` and `google-services.json` for the new ids.
- Fill in the privacy labels (App Store Connect > App Privacy) and the Data safety form (Play Console). The app collects: email, name, phone number, user id, purchase/transaction history, gameplay history, support messages and attachments, diagnostics.
- Real-money gaming licensing and age rating are in your own to-do already.
- Set the production server address with `--dart-define=API_URL=https://...`. A release build refuses plain http.
