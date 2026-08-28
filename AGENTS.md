# Agent notes

## TestFlight

Testers must only ever have the latest build. That is not optional.

Start the TestFlight workflow by pushing a `testflight-*` tag from current `main`:

```sh
git tag testflight-<short-reason>
git push origin testflight-<short-reason>
```

That is how this repo starts GitHub Actions. Do it. Do not tell the user you cannot start Actions. `gh` may be read-only; a tag push is not.

- Tag push → archive a new build on `macos-26`, then `scripts/app_store_connect.py latest-only`.
- **Actions → TestFlight → Run workflow** → `latest-only` only (no new archive, no checkbox).
- `latest-only` waits until the build is **installable** (`internalBuildState` is `READY_FOR_BETA_TESTING` or `IN_BETA_TESTING`), puts **every** app tester into every internal group and onto that build, then expires older builds. `VALID` alone is not enough.

Internal group **Alpha** auto-distributes. Apple returns `422 Cannot add internal group to a build` if you assign a build to it. That means testers **in Alpha** receive every unexpired build. An App Store Connect / “internal tester” Apple ID is **not** automatically in Alpha. The first invite (19 Aug, 0.1.0(1)) was a per-build invite. Later uploads never added that Apple ID. A personal iCloud tester who was added later got 6. After we expired 1–6, the first invitee sees “No TestFlight builds are available” with Version 0.1.0 Build 1 still shown as the last known build. Put that tester in Alpha and on the latest build before expiring anything.

Do not expire older builds until the new one is installable **and** every existing tester is entitled to it.

Apple will not replace a binary already on an iPad. After latest-only succeeds, the tester still has to open TestFlight and tap Update. If TestFlight says no builds are available, this Apple ID is not entitled to the live build.

GitHub’s TestFlight workflow **#5** is the 21 August upload of `e64d5ef` (typing gestures). Slack/GitHub “TestFlight #5 / e64d5ef / cursor bot” is that old run, not a new one. Check `gh run list --workflow=testflight.yml` for the live run number and SHA.

Details: `TESTFLIGHT.md`, `scripts/app_store_connect.py`, `.github/workflows/testflight.yml`.
