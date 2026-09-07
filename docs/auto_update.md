# SmartStore Windows auto-update

## Runtime layout

Keep `updater.exe` beside `smart_store.exe`. The updater overlays only files from the downloaded package and never removes the install directory. Customer data is not included in update ZIPs.

The configured manifest is the Appwrite Storage file `version-json` in bucket `6a89db6600013a5d5784`:
`https://fra.cloud.appwrite.io/v1/storage/buckets/6a89db6600013a5d5784/files/version-json/view?project=6a89daa60002f8486d30`

## Manifest

Start from `tools/update-server/version.json` and replace the URL, SHA-256, and size:

```json
{
  "version": "1.0.1",
  "downloadUrl": "https://fra.cloud.appwrite.io/v1/storage/buckets/6a89db6600013a5d5784/files/smartstore-1-0-1/download?project=6a89daa60002f8486d30",
  "sha256": "64 lowercase hexadecimal characters",
  "sizeBytes": 12345678,
  "releaseNotes": ["Bug fixes"],
  "mandatory": false
}
```

The client rejects non-HTTPS URLs, malformed versions, invalid hashes, wrong sizes, and hash mismatches. Network failures are silent and retried every six hours. The user sees a non-modal top-right reminder. Clicking Update downloads and verifies the package before starting `updater.exe`.

## Build and publish

1. Change `version:` in `pubspec.yaml`, for example `1.0.1+2`.
2. Build with the same semantic version so the checker compares the new build correctly:

```powershell
flutter build windows --release --dart-define=SMARTSTORE_VERSION=1.0.1
```

The build-time value is used by `UpdateService`; it is not stored in customer data.

3. Run the packaging script:
```powershell
.\tools\package_update.ps1 -Version 1.0.1
```

4. In Appwrite Storage bucket `6a89db6600013a5d5784`, upload the ZIP with file ID `smartstore-1-0-1`.
5. Upload the edited `version.json` with file ID `version-json`, replacing the old manifest.
6. Confirm that the ZIP contains `app/smart_store.exe`, `app/updater.exe`, `app/data/`, `app/flutter_windows.dll`, and plugin DLLs, but no customer database or profile data.

The script prints the SHA-256 and byte size required by the manifest.

## Server requirements

Appwrite serves both files over HTTPS. Give both Storage files public read permission, publish the ZIP first, then replace `version-json` so clients never see a manifest for a missing asset. Never put an Appwrite API key or the provided `standard_...` secret in the Flutter app. Use a server-side Appwrite function for private buckets. Use Windows Authenticode signing for the executable when a commercial signing certificate is available; SHA-256 protects package integrity but does not replace publisher signing.

In Appwrite Console, open Storage, bucket `6a89db6600013a5d5784`, and set file security so both `version-json` and the release ZIP have `Any` read permission. Keep write permission restricted to administrators. If `Any` read is not acceptable, expose the same files through a server-side HTTPS endpoint that authenticates with the Appwrite API key; never ship that key in SmartStore.

## Failure behavior

The updater verifies the package again, waits for the parent process to exit, extracts into temporary staging, backs up every replaced file, and restores those files if copying or restart fails. It does not delete unrelated files or user data. A failed download or verification returns to the normal UI and leaves the current installation running.

## Commercial rollout checklist

Before broad rollout, sign the package, host it behind controlled HTTPS infrastructure, and add a Windows smoke test covering process exit, replacement, rollback, and restart on a clean machine.
