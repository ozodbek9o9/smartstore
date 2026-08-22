# Firebase Auth and Firestore migration

The application now uses Firebase Authentication Email/Password. To preserve
the current username/password UI, an internal Firebase Auth email is derived as
`<lowercase-username>@smartstore.local`; it is never displayed in the app.

## Required console setup

1. In Firebase Console, enable **Authentication → Sign-in method →
   Email/Password**.
2. Deploy `firestore.rules` before releasing the migrated client:
   `firebase deploy --only firestore:rules,firestore:indexes`.

The rules only permit `users/{request.auth.uid}` and its descendants. Root
legacy collections are denied to all clients.

## Legacy migration

Do not deploy the restrictive rules until legacy business data has been copied.
The old root collections do not contain an owner UID, so automatically assigning
them to a user would risk exposing a business to the wrong account.

Run the migration from an administrator-controlled environment with a Firebase
service account:

```powershell
npm install firebase-admin
$env:GOOGLE_APPLICATION_CREDENTIALS='C:\secure\service-account.json'
node tools/migrate_legacy_firestore.mjs
```

The first run is dry-run only. Review every `SKIP` line. Then either use a
single known owner UID:

```powershell
node tools/migrate_legacy_firestore.mjs --apply --owner-uid FIREBASE_AUTH_UID
```

or copy `tools/legacy-ownership.example.json`, fill every legacy document ID
with its confirmed Firebase Auth UID, and run:

```powershell
node tools/migrate_legacy_firestore.mjs --apply --ownership-file tools/ownership.json
```

Verify the copied user subcollections in Firestore first. Only then run the
same command again with `--delete-legacy` to remove root legacy records. The
tool deletes only records whose destination carries its matching migration
source marker; it will never delete an unrelated pre-existing document.
Existing legacy profile documents keep their IDs: the script creates Firebase
Auth users using those IDs as UIDs, removes the old plaintext `password` field,
and leaves already nested `sellingCarts` in place.
