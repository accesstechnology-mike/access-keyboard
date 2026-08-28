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
- `latest-only` assigns the highest VALID build to every group that accepts it, then expires every older VALID build.

Internal group **Alpha** auto-distributes. Apple returns `422 Cannot add internal group to a build` if you assign a build to it. That means the group already receives every unexpired build. Treat it as success and still expire older builds. Do not fail the job.

The App Store Connect / developer Apple ID is an internal tester. A personal iCloud Apple ID is usually an external tester. If groups are pinned to different builds, those two accounts show different versions. That is the 0.1.0(1) vs 0.1.0(6) bug. Expire old builds; do not pin a group to a specific build.

Apple will not replace a binary already on an iPad. After latest-only succeeds, the tester still has to open TestFlight and tap Update.

GitHub’s TestFlight workflow **#5** is the 21 August upload of `e64d5ef` (typing gestures). Slack/GitHub “TestFlight #5 / e64d5ef / cursor bot” is that old run, not a new one. Check `gh run list --workflow=testflight.yml` for the live run number and SHA.

Details: `TESTFLIGHT.md`, `scripts/app_store_connect.py`, `.github/workflows/testflight.yml`.
