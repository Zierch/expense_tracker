# Privacy Policy — Expense Tracker

_Last updated: 17 October 2026_

Expense Tracker is an offline, Android-only personal finance app. This policy
describes exactly what the app does with your information. It is written to be
read, not to be survived.

## The short version

The app has no servers, no account system of its own, no analytics, no crash
reporting, and no advertising. Every transaction you enter stays in a private
database on your phone. The only time the app itself sends anything off your
device is when you yourself tap **Backup to Google Drive** for a specific month —
and it goes to _your_ Google Drive, not to the developer. Android's own
system-level backup is switched off for this app, and the newer cross-platform
transfer route has no counterpart for it to carry anything to; see "Android Auto
Backup is turned off" below.

The developer of this app cannot see your data. There is no backend that could
receive it.

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

## Android permissions

- `INTERNET` — required to reach Google Drive when you export.
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
named in the rules file. This app is Android-only, declares no such counterpart,
and has no iOS version to receive anything, so that route has nothing to carry.

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
