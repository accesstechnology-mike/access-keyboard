# Releasing access: keyboard

TestFlight and the App Store are different pipelines. A TestFlight tag never
creates an App Store version and never submits for App Review.

The App Store command is `scripts/submit_app_store.py`. It uses the same App
Store Connect API key as the TestFlight upload
(`APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`,
`APP_STORE_CONNECT_API_KEY`). The app is looked up from the bundle id in the
Xcode project. The script does not hard-code an App Store id.

## Which tag does what

| Start it with | What it does |
| --- | --- |
| `testflight-*` | Archive on `macos-26`, upload, then TestFlight `latest-only`. Does not submit to the App Store. |
| `sync-testflight-*` | TestFlight `latest-only` on Ubuntu. No archive. |
| **Actions → TestFlight → Run workflow** | Same as `sync-testflight-*`. |
| `release-*` | Archive, upload, TestFlight `latest-only`, then submit that build to the App Store. |
| **Actions → App Store → Run workflow** | Submit a build that is already uploaded. No archive. |

`release-*` spends an Apple Development certificate, the same as `testflight-*`.
Do not push it to submit a build that is already in App Store Connect. Use
**Actions → App Store** for that. If the archive succeeded and the submit step
failed, re-run **Actions → App Store** with that version and build number. Do
not push a second `release-*` tag.

There is no tag that submits an already-uploaded build. Version and build
number are workflow inputs, because a tag cannot carry both cleanly.

## What the submit step does

For the marketing version and build number it:

1. Waits until the build has finished processing (same installable check as TestFlight: `VALID`, not expired, and not blocked on export compliance). The only build-record write is the existing export-compliance answer (`usesNonExemptEncryption` false) when Apple has not stored one yet. The binary already declares that.
2. Creates the iOS App Store version, or reuses it when that version string already exists.
3. Attaches the build. The build's pre-release version must be the same marketing version. A mismatch fails the run.
4. Sets the **en-GB What's New** text from `release-notes/<version>.txt`. Leading and trailing whitespace in the file is not sent. No other locale is written.
5. Sets the release type to automatic after approval (`releaseType` `AFTER_APPROVAL`) before sending the submission, so approval releases the version without another step.
6. Submits it for App Review through a review submission that contains **only** this version.

Any failed step exits non-zero and prints `App Store submit failed:` plus Apple's response. The GitHub job fails with that log.

The command does not change the description, keywords, promotional text, URLs, screenshots, privacy labels, pricing, phased release, or App Review notes. A new version inherits the previous version's listing. The request builder refuses any other attribute.

## Release notes

Add `release-notes/<marketing version>.txt` in the same commit as the
`MARKETING_VERSION` bump. The App Store primary language is English (UK), so
this file is the en-GB What's New text and nothing else. The workflow will not
invent text, and it will not submit a version whose file is missing or empty.

`1.0.1` is `release-notes/1.0.1.txt`.

Check the file locally, with no network:

```sh
python3 scripts/submit_app_store.py --check-notes --version 1.0.1 --build 23
```

`--version` and `--build` must match `MARKETING_VERSION` and
`CURRENT_PROJECT_VERSION` in the Xcode project. `--from-project` reads those
settings. That is what the `release-*` job runs after the upload script has
written the new build number into the project on the runner.

## Submit 1.0.1 build 23

Build 23 is already uploaded. Do not archive it again. After this is on `main`,
open **Actions → App Store → Run workflow** on `main` and enter:

| Input | Value |
| --- | --- |
| version | `1.0.1` |
| build | `23` |
| dry run | off |

Or, with the GitHub CLI:

```sh
gh workflow run "App Store" --ref main -f version=1.0.1 -f build=23 -f dry_run=false
```

A dry run reads App Store Connect and prints the plan. It does not create a
version, edit What's New, attach a build, or submit:

```sh
gh workflow run "App Store" --ref main -f version=1.0.1 -f build=23 -f dry_run=true
```

The same dry run from a machine that has the API key:

```sh
python3 scripts/submit_app_store.py --version 1.0.1 --build 23 --dry-run
```

## Re-runs

Re-running is safe.

- The version string already exists: it is reused, not created again.
- What's New, the attached build, or the release type already match: that write is skipped.
- The version is already `WAITING_FOR_REVIEW` or `IN_REVIEW` with this build and this What's New: the run stops successfully and does not submit a second time. If the text or the build differs, the run fails and leaves the submission alone.
- A previous rejection whose review submission contains only this version is cancelled and submitted again.
- A draft review that contains anything other than this version fails the run. Nothing else is submitted with the app.
- Another version already in review fails the run.
- A version that is already on sale is left as it is when the build and What's New match. A version Apple has replaced or removed from sale is not resubmitted.

A version that is already approved and waiting for a manual release
(`PENDING_DEVELOPER_RELEASE`) is not released by calling the manual release
endpoint. The run tries to switch it to automatic. If Apple refuses that
change, the job fails and someone still has to release it in App Store Connect.

## A new App Store upload

1. Bump `MARKETING_VERSION` on the app and the extension when the user-visible version changes, and add `release-notes/<version>.txt`.
2. Leave `CURRENT_PROJECT_VERSION` for the upload script. It advances past the latest TestFlight build during the archive and does not commit that change.
3. From current `main`:

```sh
git tag release-<short-reason>
git push origin release-<short-reason>
```

That tag is the whole release. It archives, uploads, gives testers that build,
and submits the App Store version. Testers still only get the latest build.
See `TESTFLIGHT.md` for certificates, TestFlight groups, and the archive itself.
