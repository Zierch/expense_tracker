# Privacy Policy — Expense Tracker

_Last updated: 19 November 2026_

Expense Tracker has two builds. The Android app is offline and keeps everything
in a local database on your phone. The web app stores your records in Supabase,
under an account you sign in to. They do not sync with each other; a transaction
added on one appears only there. This policy describes both, and is written to be
read, not to be survived.

## The short version

The app has no servers, no account system of its own, no analytics, no crash
reporting, and no advertising. Every transaction you enter stays in a private
database on your phone. The app sends nothing off your device unless you hand it
a destination yourself: the backup **you** tap to Google Drive, and the PDF
report **you** share to an app of your choosing. The one thing it does on its own
is the update check against GitHub, which involves no part of your data at all.
Android's own
system-level backup is switched off for this app, and the newer cross-platform
transfer route has no counterpart for it to carry anything to; see "Android Auto
Backup is turned off" below.

On Android the developer cannot see your data; there is no backend that could
receive it. On web the data sits in the project's Supabase database, protected by
Row Level Security so that only the signed-in owner can read or write their own
rows. The developer operates that database but has no application that displays
your records.

## The web build

The web build is a different store, not a second copy of the Android database.

- Records are saved in a Supabase PostgreSQL database in the
  `ap-southeast-1` (Singapore) region.
- You sign in with an email address and password. Supabase owns the account; the
  app has no account system of its own.
- Row Level Security is enabled on `categories`, `subcategories` and
  `transactions`. A row is readable and writable only when its `user_id` equals
  the signed-in user's id. This is what limits an anon key, which is present in
  every web build, to your data alone.
- The app does not send analytics, crash reports or advertising data. The only
  network traffic is to Supabase for your own records.
- Signing in stores a session in your browser. Signing out clears that session;
  it does not delete your records.

### Deleting your account and data

Sign out in Settings, then ask the operator of the deployment to delete your
SupabaseAuth user. Deleting the `auth.users` row cascades to that user's
categories, subcategories and transactions — the foreign keys in
`docs/supabase_schema.sql` are `ON DELETE CASCADE`, so no records remain behind.

## What the app stores on your device

Your transactions are saved in a SQLite database inside the app's private
storage area. Each record contains:

- the date of the transaction
- whether it is income or an expense
- the amount, in Indonesian rupiah (IDR)
- the category and subcategory you assigned
- the free-text note you optionally typed

Other apps on your phone cannot read this database. It is deleted when you
uninstall the app or clear its data from Android's app settings.

## What leaves your device, and only when you ask

When you open the Backup screen, choose a month, and tap the export action:

1. The app assembles that one month of data into a JSON file named
   `expense-tracker-YYYY-MM.json`.
2. It uploads that file to a folder called `Expense Tracker` in your own Google
   Drive, creating the folder on first use.

The file is readable JSON. It records the app name, a schema version, the
currency, the period covered, and the time the export was made. For each
transaction it contains an internal `id`, the `date`, the `type` (income or
expense), the `category`, the `subcategory`, the `amount`, and the `note`. It
also contains a monthly summary: total income, total expense, the balance, and
per-category totals. Notes you typed are included verbatim, so please do not put
information in a note that you would not want stored in your Google Drive.

Nothing is uploaded on a schedule, in the background, or automatically. If you
never tap the export action, the app never contacts Google Drive at all. Signing
in reaches Google's sign-in service, which is a different thing from your
Drive.

Re-exporting the same month replaces the previous file rather than adding a
second copy.

### When you export a PDF report

On the Backup screen you can also build a PDF of any date range. This is a local
file, not an upload:

1. The app draws the report on your phone and writes it to its own private cache
   area.
2. Android's share sheet opens, and you choose where it goes — Files, a chat app,
   mail, or a PDF viewer.

The app keeps no second copy of that file, and nothing about it is sent to the
developer or to Google: whoever receives the PDF is whoever you picked. Treat the
file as you would any document containing your transactions, including any notes
you typed.

## What the app does not collect

- No usage analytics, telemetry, or crash reports
- No advertising identifiers, and no advertising SDKs
- No location, contacts, camera, microphone, or files outside the app
- No account registration, and no email address is sent anywhere by the app
- No data is sold, shared, or transmitted to the developer or to any third party

## Google Sign-In and what the app can access

Google Drive backup requires signing in with a Google account. The app requests a
single permission, the `drive.file` scope. It is deliberately narrow — the app
gets no access to anything it did not create itself:

- The app can see and manage **only the files it created itself**.
- The app **cannot** read, list, modify, or delete any other file in your Drive —
  not your documents, not your photos, not files made by other apps.

Your Google account credentials are handled entirely by Google's own Sign-In SDK
on your device. The app never sees your password, and it keeps no copy of your
access token in its own storage; Google's SDK manages the session on your
device.

## Being a test user

Google sign-in for this app is in _Testing_ mode, which is how a small app avoids
Google's brand-verification process. That mode only works for accounts the
developer has listed as test users, so to use Drive backup you have to tell the
developer which Google address to add, and the developer will then be able to see
that address. It is used to grant access and for nothing else: no mailing list,
no profiling, and no sharing. Ask through the issue tracker if you want it
removed once you no longer need access.

## Update checks

The app can check for its own newer release. This is how it works, exactly:

- **When:** once, shortly after the app opens, and whenever you tap *Check for
  update* on the Backup screen. Nothing runs in the background.
- **What is sent:** one HTTP request to GitHub's public API
  (`api.github.com/repos/Zierch/expense_tracker/releases/latest`) asking for the
  newest published release of the app. No account, no token, no identifier, and
  no part of your data is attached — GitHub sees your IP address and the
  request's User-Agent string, as it would any page load.
- **What comes back:** the release tag, and the download address of its APK.
  If the release is newer than your installed one, the app lets you download
  that APK to its own cache and, after verifying it against the SHA-256
  checksum published in the release notes itself, hands it to Android's
  installer. You confirm every step; Android additionally asks, once per app,
  for permission to install from this source on Android 8 and above.

Declining the download installs nothing. Turning off network access to the app
(skipping Wi-Fi/Mobile data for it in Android settings) removes these requests
entirely; the app keeps working offline.

## Android permissions

- `INTERNET` — required to reach Google Drive when you export, and to check for
  and download app updates as described above.
- `REQUEST_INSTALL_PACKAGES` — required so the app can hand the downloaded
  update APK to Android's installer. It carries no data access; the user still
  confirms each install.
- `USE_BIOMETRIC` and `USE_FINGERPRINT` — these come from the `androidx.biometric`
  library, which Google's Sign-In SDK pulls in for its credential handling. This
  app itself does not use biometrics, and it never asks you for a fingerprint.
  The permissions are install-time only and show no prompt.

## Android Auto Backup is turned off

Android can normally copy app data to your Google account as part of Auto Backup.
This app disables that (`android:allowBackup="false"`) and, on Android 12 and
above, also excludes every data domain from both cloud backup and
device-to-device transfer in its `data_extraction_rules.xml`. Your financial
database is therefore not copied into Google's backup service, and a
device-to-device transfer to a new phone does not carry it either. The Backup
screen is the one supported way to get your data off the device.

Android 16 QPR2 (API level 36.1) added a third route, cross-platform transfer.
It moves data between the same app on two platforms, and only to the counterpart
named in the rules file. The Android build declares no such counterpart: it has
no iOS version, and the web build is served separately rather than receiving a
device transfer. That route therefore has nothing to carry from Android.

## Revoking access

You can withdraw the app's access to your Google Drive at any time:

- In the app, use the **Disconnect** action on the Backup screen. This revokes the
  grant and signs you out.
- Or from Google directly, at
  [myaccount.google.com/permissions](https://myaccount.google.com/permissions).

Revoking access does not delete files the app already created in your Drive. If
you want those gone, delete the `Expense Tracker` folder in your Drive yourself.

## Deleting your data

- **On your device:** uninstall the app, or use Android's _Clear data_ option.
  This erases the local database permanently.
- **In your Google Drive:** delete the `Expense Tracker` folder, or the individual
  `expense-tracker-YYYY-MM.json` files, yourself. The app is able to delete the
  files it created — the `drive.file` scope covers managing them — but it never
  does so on its own, because withdrawing the app's access is not the same as
  asking it to erase your backups.

## Children

This app is not directed at children and does not knowingly collect information
from anyone.

## Changes to this policy

If this policy changes, the updated version will be committed to the same
repository that contains the app's source code, with a new "last updated" date.

## Contact

Questions or corrections are welcome through the issue tracker of the repository
this app came from.
