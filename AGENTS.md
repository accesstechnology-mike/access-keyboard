# Agent notes

## TestFlight

Testers must only ever have the latest build. That is not optional.

Start the TestFlight workflow by pushing a `testflight-*` tag from current `main`:

```sh
git tag testflight-<short-reason>
git push origin testflight-<short-reason>
```

That is how this repo starts GitHub Actions. Do it. Do not tell the user you cannot start Actions. `gh` may be read-only; a tag push is not.

- `testflight-*` tag → archive a new build on `macos-26`, then `latest-only`. Do not do this when you only need to fix testers. Repeated CI archives exhaust Apple Development certificates (`Choose a certificate to revoke`).
- `sync-testflight-*` tag → `latest-only` on Ubuntu, no archive. Use this to reinvite testers onto the live build.
- **Actions → TestFlight → Run workflow** → same as `sync-testflight-*`.
- `latest-only` waits until the build is **installable**, puts **every** app tester into every internal group and onto that build, then expires older builds. Do not expire if tester listing fails. `GET /v1/apps/{id}/betaTesters` can 403 this API key; also query `/v1/betaTesters?filter[apps]=`, each group's testers, and each build's individual testers. Installable means `VALID` and not expired. If Apple sends `internalBuildState`, treat `PROCESSING` / export-compliance states as not ready; if that field is missing (`VALID/no-internal-state`), `VALID` is enough. Do not wait 45 minutes for a field Apple never returns. App Store Connect JWTs expire after 20 minutes; refresh them during that wait. A 401 `NOT_AUTHORIZED` mid-wait is an expired token, not a revoked key.

Internal group **Alpha** auto-distributes. Apple returns `422 Cannot add internal group to a build` if you assign a build to it. Testers **in Alpha** with a live invite receive every unexpired build.

A TestFlight row under **Previously Tested** that says “No TestFlight builds are available” and still shows 0.1.0 (1) is a tester without a live invite (`REVOKED` or `NOT_INVITED`), not a missing build. Adding them to Alpha is a no-op. `POST /v1/betaTesters` may include **only one** relationship. Creating on a build can return an id while Apple still reports `NOT_INVITED` — trust Apple’s `state`. App Store Connect **users** are only `admin@accesstechnology.co.uk` and `mike@accesstechnology.co.uk`. `grace@accesstechnology.co.uk` (GC avatar) is not a user, so Alpha returns `409 Tester(s) cannot be assigned`. `sync-testflight-asc-user-invite` sent her an App Store Connect **MARKETING** invite (`userInvitations` id `ea1208e6-72af-4d11-b923-59d13c5c4cd7`, this app only). She must accept that Apple email before internal TestFlight can work. The old TestFlight page will not update. Then push `sync-testflight-*` (no archive). `mike.thrussell@googlemail.com` is EMAIL `INVITED` without being a user. Live states are only `INVITED`, `ACCEPTED`, `INSTALLED`. Do not treat `409 Tester(s) cannot be assigned` as “already exists”. Do not push `testflight-*` until someone revokes spare Apple Development certificates.

Do not expire older builds until the new one is installable **and** every emailed tester has a live invite. `latest-only` must fail if anyone is still `REVOKED` or `NOT_INVITED`.

Apple will not replace a binary already on an iPad. After a new invite, the tester must accept the email and install. Force-quit TestFlight if the old revoked page is still showing.

GitHub’s TestFlight workflow **#5** is the 21 August upload of `e64d5ef` (typing gestures). Slack/GitHub “TestFlight #5 / e64d5ef / cursor bot” is that old run, not a new one. Check `gh run list --workflow=testflight.yml` for the live run number and SHA.

Details: `TESTFLIGHT.md`, `scripts/app_store_connect.py`, `.github/workflows/testflight.yml`.
