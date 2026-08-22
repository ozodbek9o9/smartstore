# SmartStore Windows auto-update

## Runtime layout

Keep `updater.exe` beside `smart_store.exe`. The updater overlays only files from the downloaded package and never removes the install directory. Customer data is not included in update ZIPs.

The configured manifest URL is `https://neowhite-studio.vercel.app/smartstore/version.json`.

## Manifest

Start from `tools/update-server/version.json` and replace the URL, SHA-256, and size:

```json
{
  "version": "1.0.1",
  "downloadUrl": "https://neowhite-studio.vercel.app/smartstore/SmartStore-1.0.1.zip",
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

4. Upload `dist/SmartStore-1.0.1.zip` and the updated `version.json` to the HTTPS server.
5. Confirm that the ZIP contains `app/smart_store.exe`, `app/updater.exe`, `app/data/`, `app/flutter_windows.dll`, and plugin DLLs, but no customer database or profile data.

The script prints the SHA-256 and byte size required by the manifest.

## Server requirements

Serve both files over HTTPS with stable `Content-Length` headers. Do not redirect to HTTP. Publish a complete ZIP atomically, then publish `version.json` last. Use Windows Authenticode signing for the executable when a commercial signing certificate is available; SHA-256 protects package integrity but does not replace publisher signing.

## Failure behavior

The updater verifies the package again, waits for the parent process to exit, extracts into temporary staging, backs up every replaced file, and restores those files if copying or restart fails. It does not delete unrelated files or user data. A failed download or verification returns to the normal UI and leaves the current installation running.

## Commercial rollout checklist

Before broad rollout, sign the package, host it behind controlled HTTPS infrastructure, and add a Windows smoke test covering process exit, replacement, rollback, and restart on a clean machine.
