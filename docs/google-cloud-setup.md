# Google Cloud Console setup (Drive backup)

Everything the app's Google Drive backup needs lives in one Google Cloud project
that **you** own. This page is the click-by-click version of the "Using your own
Google OAuth client" section in `README.md`, with the exact values for this app
already filled in.

What this gets you: the **Sign in with Google** button on the Backup page works,
for you and for up to 100 accounts you list — your own account is part of that
cap. What it does *not* require: no custom
domain, no hosted privacy policy, no app-verification review, no Google Play
listing, and no server of any kind. Each person's backup is written to their own
Google Drive.

Budget roughly 10 minutes.

**Prerequisite:** the Google account that owns the project must have
**2-step verification (2SV, also called MFA) enabled**. Since 13 May 2025 Google
Cloud refuses Console access for accounts without it and shows *"Google Cloud
access blocked"*. Turn it on at <https://myaccount.google.com/signinoptions/twosv>
(the *Enable MFA* button in that message leads to the same page), then wait a
few minutes and refresh for the block to lift.

## Values this app expects

| Thing | Value |
| --- | --- |
| Package name | `com.zierch.expense_tracker` |
| Release signing SHA-1 | `B2:F5:0E:9C:44:F5:72:4B:9E:17:B5:7B:D7:B6:A3:E6:24:F4:2C:AE` |
| Debug signing SHA-1 | `C6:24:A6:05:EE:B9:F7:47:47:C6:E7:54:09:70:3C:72:DA:77:E5:F1` |
| OAuth scope requested at runtime | `https://www.googleapis.com/auth/drive.file` |
| Where the **Web application** client ID goes | `lib/data/services/google_config.dart` → `serverClientId` |

The two fingerprints come from the keystores this project was signed with: the
release one is in `android/app/release-keystore.jks` (alias `expense-tracker`,
valid to 2054-03-04), the debug one is the Android SDK's
`%USERPROFILE%\.android\debug.keystore` on Windows (`~/.android/debug.keystore`
on Linux or macOS; alias `androiddebugkey`, password
`android`) that Gradle creates on the first debug build. Re-check them any time
with:

```bash
keytool -list -v -keystore android/app/release-keystore.jks -alias expense-tracker
keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android
```

## Steps

Do all of this while signed in to the Google account that will own the project.
That account runs the OAuth client on everyone's behalf; the backups themselves
go to each user's own Drive, never to the owner's.

### 1. Create a project

1. Open <https://console.cloud.google.com/>.
2. Click the project picker in the top bar (next to "Google Cloud") →
   **New project**.
3. Name: `Expense Tracker`. Location: **No organisation**.
4. **Create**, wait for the notification, then select the new project in the
   picker so everything below happens inside it.

### 2. Enable the Google Drive API

1. In the search bar at the top, type `Google Drive API` and pick it from the
   results (or go to **APIs & Services** → **Library**).
2. Click **Enable**.

Sign-in will succeed without this and every export will then fail with a 403, so
it is worth double-checking later under **APIs & Services** →
**Enabled APIs & services**: *Google Drive API* must be listed.

### 3. Configure the OAuth consent screen

Recent projects show this as a product called **Google Auth Platform**;
older ones call it **OAuth consent screen** under *APIs & Services*. Both lead
to the same settings.

1. Open **Google Auth Platform** (or *APIs & Services → OAuth consent screen*).
2. On first visit you get a **Get started** wizard:
   - **App information** — App name: `Expense Tracker`; User support email:
     your own Gmail address.
   - **Audience** — choose **External**. (*Internal* only exists for Google
     Workspace organisations.)
   - **Contact information** — your own Gmail address again.
   - Tick the policy checkbox, then **Create**.
3. Leave the publishing status at **Testing**. Do **not** press *Publish app*:
   staying in Testing is exactly what keeps this out of Google's verification
   review, and the app only requests a non-sensitive scope.

### 4. Add test users

Still on the Google Auth Platform: open the **Audience** tab → **Test users** →
**+ Add users**.

- Add your own Gmail address first.
- Then add every friend who should be able to back up, using **the Google
  account they will sign in with** (not necessarily their contact address).
  Google caps this list at 100 accounts.

An account that is missing here fails at sign-in with `access_denied`, no matter
how correct everything else is.

### 5. Create the Android client for release builds

Google matches an Android app by package name **plus** signing certificate, so
this client carries no ID that goes into the code.

1. Open the **Clients** tab → **Create client**.
2. Application type: **Android**.
3. Name: `Expense Tracker Android (release)`.
4. Package name: `com.zierch.expense_tracker`.
5. SHA-1 certificate fingerprint: paste
   `B2:F5:0E:9C:44:F5:72:4B:9E:17:B5:7B:D7:B6:A3:E6:24:F4:2C:AE`
   (colons and letter case are both fine).
6. **Create**.

### 6. (Optional) Create the Android client for debug builds

Only needed if you want Drive backup to work in `flutter run` / debug builds.
Repeat step 5 with the same package name, the name
`Expense Tracker Android (debug)`, and the debug fingerprint
`C6:24:A6:05:EE:B9:F7:47:47:C6:E7:54:09:70:3C:72:DA:77:E5:F1`.

If you ever delete `%USERPROFILE%\.android\debug.keystore`, Android regenerates
it with a new fingerprint and this client stops matching; recreate the client.

### 7. Create the Web application client (the one the code uses)

Android identifies the app, but the Google Sign-In SDK still needs a *server*
client ID to obtain the Drive scope. This is the single value that ends up in
the repository.

1. **Clients** tab → **Create client**.
2. Application type: **Web application**.
3. Name: `Expense Tracker web (server client ID)`.
4. Leave **Authorised JavaScript origins** and **Authorised redirect URIs**
   empty.
5. **Create**, then copy the **Client ID** — a long string ending in
   `.apps.googleusercontent.com` (about 70 characters).
6. Ignore the **Client secret** next to it. This app must never need a secret;
   if Google ever asks this app for one, something has been configured wrongly.

### 8. Paste the client ID into the app

In `lib/data/services/google_config.dart`:

```dart
static const String serverClientId = '<your-id>.apps.googleusercontent.com';
```

Committing a client ID is intentional and correct: it identifies the
application, not the user, and the distributed APK has to carry it. The
**secret** is the thing that must never appear in this project, and
`test/release_config_test.dart` enforces that.

### 9. Rebuild and redistribute the APK

The client ID is compiled into the app, so an APK built before this step cannot
sign in. After pasting:

```bash
flutter build apk --release
```

Then replace the APK attached to the GitHub Release. Friends who kept the older
APK would keep seeing the sign-in failure, so tell them to install the new one.

### 10. Give Google a few minutes

New clients and new test users take a little while to propagate. A
`clientConfigurationError` in the first few minutes after creating a client is
usually just that. Console changes can also need the app to be restarted (some
devices cache the rejected response until the app is swiped away).

## Verification checklist

- [ ] **APIs & Services → Enabled APIs & services** lists *Google Drive API*.
- [ ] **Google Auth Platform → Audience** shows User type *External*,
      Publishing status *Testing*, and the test users you added.
- [ ] **Google Auth Platform → Clients** lists three entries: two Android
      (release, optionally debug) and one Web application.
- [ ] The pasted `serverClientId` ends in `.apps.googleusercontent.com` and is
      not the `PASTE_WEB_CLIENT_ID_HERE` placeholder.
- [ ] On the phone: Backup page → **Sign in with Google** → the consent sheet
      mentions access to *files it creates* only → after signing in, the export
      button succeeds and Drive shows `My Drive → Expense Tracker →
      expense-tracker-<YYYY-MM>.json`.

## What friends will see (limits of Testing mode)

- The consent sheet says **"Google hasn't verified this app"**. That is
  expected: they tap *Advanced* → *Go to Expense Tracker (unsafe)*. Nothing is
  wrong, and no review is needed for the `drive.file` scope. Tapping through it
  is only safe because the APK came from this project's
  [Releases page](https://github.com/Zierch/expense_tracker/releases) — the
  screen cannot tell this app apart from an impostor, so ask everyone to install
  it from there and nowhere else, and to check the file against the SHA-256 in
  the release notes
  ([Verifying a download](../README.md#verifying-a-download)). An APK forwarded
  through a chat app has no provenance at all.
- **100 test users maximum.** Beyond that the Testing route stops working and
  the app would need Google's verification review — deliberately out of scope
  for this app.
- Google documents that a project in **Testing** with an *External* audience
  issues short-lived (7-day) refresh tokens. This app authorises on the device
  and re-signs in silently, so normally you will never notice; but if the Backup
  page starts asking for a sign-in again after some days, that is why, and
  tapping *Sign in with Google* once puts it right.
- Anyone can revoke access at
  <https://myaccount.google.com/> → *Data & privacy* → *Third-party apps &
  services*. The Backup page's **Disconnect** button does the same from inside
  the app; plain **Sign out** deliberately keeps the grant so the next export
  does not ask again.
- Deleting the *Expense Tracker* folder in Drive does not stop the app: it
  recreates the folder on the next export. Files already uploaded stay in Drive
  even after signing out, disconnecting, or uninstalling.

## Troubleshooting

| Symptom | Cause |
| --- | --- |
| "Google Cloud access blocked" (2SV/MFA required) | The account owning the project has no two-step verification. Enable it, wait a few minutes, refresh; sign out of and back into the Console if it persists. This is a Console-owner requirement only: people using the app's Drive export do not need 2SV on their own accounts. |
| `clientConfigurationError` at sign-in | Package name, SHA-1 or client type mismatch, an APK signed with a different key than the one registered (debug APK vs release client), or a Console change that has not propagated yet. |
| `access_denied`, or "app is blocked" | The Google account is not in **Test users**. |
| Sign-in succeeds, export fails with 403 | *Google Drive API* is not enabled in **this** project. |
| Backup page shows **"Google Drive is not ready"** with *"Google Client ID is not configured."* | `serverClientId` is still the placeholder, or the APK predates the paste. |
| The backup folder is "missing" in the Drive UI | The `drive.file` scope only exposes files this app created; the folder appears after the first successful export. |
| Drive export works for you, not for a friend | That friend's Gmail address is not on the test-user list, or they are on an older APK. |

## Maintenance

- **New signing key** (rotated keystore, or Play App Signing after a Play
  release): add another **Android** client with the new SHA-1. The old one can
  stay; every certificate you ship with needs its own entry.
- Keep the `drive.file` scope. Moving to a broader Drive scope (`drive`,
  `drive.readonly`) drags the app into Google's sensitive/restricted scope
  review, which is the one thing this setup exists to avoid.
- The project here may be edited freely: renaming the app, changing the support
  email or adding test users does not invalidate the client ID already baked
  into a shipped APK. Only the package name and the signing certificate are
  bound to the Android clients.
