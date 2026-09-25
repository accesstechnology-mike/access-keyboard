# TestFlight, step by step

This is a universal keyboard (`access: keyboard`) that runs on **iPhone and iPad** (iOS/iPadOS 18). Archive the **AccessKeyboard** scheme. That already embeds `AccessKeyboardExtension`. You cannot do the upload from Linux; the last mile is Xcode on a Mac signed into team `A688GUK8XK` (Access Technology North Limited).

Debug and Release builds call the live Fix proxy at `https://access-keyboard.vercel.app/api/fix`. Both send `Authorization: Bearer` with `AK_FIX_PROXY_SECRET`. That value is not in git: copy `Secrets.xcconfig.example` to `Secrets.xcconfig`, and put the same string in Vercel as `FIX_PROXY_SECRET` (Production and Preview). GitHub deploys do not wipe Vercel env vars. Do not enable Vercel Authentication; the keyboard cannot log in.

## 0. Confirm the project is ready

On this repo:

```sh
python3 scripts/check-testflight.py
```

That checks the 1024 icon has no alpha, both targets share one marketing version and one build number, privacy manifests declare UserDefaults (`CA92.1`), and the live Fix endpoint answers.

If you change the app after a TestFlight upload, bump `CURRENT_PROJECT_VERSION` on **both** the app and the extension (Debug and Release). Apple rejects a reuse of the same build number.

## 1. Apple Developer identifiers

In [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list) for team `A688GUK8XK`, create these if they are missing. Automatic signing will often create them the first time you archive, but App Groups do not always appear on their own.

| Kind | Identifier |
| --- | --- |
| App ID | `app.access.keyboard.6M3Z27M69P` |
| App ID | `app.access.keyboard.6M3Z27M69P.extension` |
| App Group | `group.6M3Z27M69P.app.access.keyboard` |

On **both** App IDs, enable App Groups and tick `group.6M3Z27M69P.app.access.keyboard`. The keyboard extension will not see colour settings without that group.

## 2. App Store Connect record

1. Open [App Store Connect](https://appstoreconnect.apple.com) → **My Apps** → **+**.
2. Platform: **iOS**.
3. Name: `access: keyboard`.
4. Primary language: English (UK) if that is the team default, otherwise English (US). The keyboard’s primary language is `en-US`.
5. Bundle ID: `app.access.keyboard.6M3Z27M69P`.
6. SKU: use the bundle ID (`app.access.keyboard.6M3Z27M69P`) unless you already have a SKU scheme.
7. User Access: Full Access.

This app is **universal** (`TARGETED_DEVICE_FAMILY = "1,2"`, iPhone + iPad) and needs **iOS/iPadOS 18.0**. In App Store Connect, leave device availability set so **both iPhone and iPad** are offered the build — if the app was previously created as iPad-only, an admin (Mike) must flip iPhone availability on for the app in App Store Connect after the first universal binary is uploaded, or iPhone testers will still see "no builds available". The binary now supports both; ASC just has to advertise it.

Export compliance is already answered in the project (`ITSAppUsesNonExemptEncryption = NO`). If App Store Connect still asks, choose **No**.

## 3. Privacy answers

Use these only; they match the privacy manifests and the Fix proxy.

| Question | Answer |
| --- | --- |
| Tracking? | No |
| Data collected? | Yes — Other User Content |
| Linked to identity? | No |
| Used for tracking? | No |
| Purpose | App Functionality |
| When | Only if the tester taps **Fix** |
| Third party? | Yes. The Release proxy at `https://access-keyboard.vercel.app/api/fix` forwards that field to OpenAI with `store` disabled. The proxy does not keep the text. Ordinary keystrokes stay on the device. |
| Colour settings / predictions | On-device only (App Group + UserDefaults) |

Internal TestFlight does not need a public privacy-policy URL. External testers / App Review will. After you deploy `proxy/public/privacy.html`, the URL is `https://access-keyboard.vercel.app/privacy.html`.

## 4. Archive and upload from Xcode

1. Open `AccessKeyboard.xcodeproj` on a Mac.
2. Sign in to Xcode with the Apple ID for team `A688GUK8XK`.
3. Select the **AccessKeyboard** scheme, **Any iOS Device (arm64)** — not a simulator.
4. Confirm both targets use **Automatically manage signing** and team `A688GUK8XK`.
5. Product → **Archive**. That uses Release, so Fix will hit the Vercel URL.
6. Organizer → **Distribute App** → **App Store Connect** → **Upload**.
7. Leave “Upload your app’s symbols” on. Do not choose Development or Ad Hoc; those never reach TestFlight.
8. Wait until App Store Connect → TestFlight shows the build as **Ready to Test**. Processing often takes 10–30 minutes. A yellow “Missing Compliance” banner is answered in step 2.

If signing fails on the extension, the App Group is missing from one of the App IDs. Fix that in the Developer portal, then archive again.

If an archive fails with `Choose a certificate to revoke. Your account has reached the maximum number of certificates.`, free a Development cert slot with **Actions → Revoke spare Development certs → Run workflow** (or `gh workflow run revoke-dev-certs.yml -f keep=1 -f execute=true`); it runs `python3 scripts/app_store_connect.py revoke-spare-development-certs --keep 1 --execute` to revoke the oldest Apple Development / `IOS_DEVELOPMENT` certs while keeping the newest. Automatic signing recreates provisioning profiles on the next archive.

## 5. Internal testers (do this first)

Internal testers skip Beta App Review. They must be Users in App Store Connect (Admin / App Manager / Developer / Marketing / Sales).

1. TestFlight → **Internal Testing** → create a group, e.g. `Access Technology` / **Alpha**.
2. Add **every** App Store Connect user who should test, including the developer/test Apple ID. Being an Admin does not put that Apple ID in the group. A first-build email invite is a per-build invite; it will not follow later uploads.
3. Turn on **Automatically Distribute Builds**. Do not add a specific old build. Uploads wait until the new build is installable, put every existing tester in the internal groups and on that build, then expire older builds.

Each person installs **TestFlight** from the App Store on an **iPhone or iPad running iOS/iPadOS 18**, accepts the invite, and installs `access: keyboard`. Both device families are offered the build once ASC advertises iPhone availability (see §2).

Every upload assigns the latest build to every group and expires the rest. There is no opt-in. **Actions → TestFlight → Run workflow** does the same for the build already in App Store Connect, without cutting a new archive. Testers who still have an old install must open TestFlight and tap Update; Apple cannot replace an already-installed binary by itself.

## 6. External testers (needs Beta Review)

Do this only after an internal install works, including Full Access and Fix.

You can do all of this from CI with the App Store Connect key in repository
secrets — no Mac and no browser login needed. `gh` is read-only here, so start
Actions with a tag push (see `AGENTS.md`):

```sh
# See where things stand first (no changes): external group, external build
# state, Beta Review readiness, and any public link.
git tag status-testflight-check
git push origin status-testflight-check

# Invite an external tester by email. The tag payload is the email. This
# creates the "External Testers" group if missing, assigns the latest build,
# submits it for Beta App Review, enables the public link, and emails the tester.
git tag invite-tester-someone@example.com
git push origin invite-tester-someone@example.com
```

**Actions → TestFlight invite → Run workflow** does the same with per-run
options (`mode` = status or invite, external vs internal, group name, whether to
submit for review, whether to enable the public link).

Under the hood these run `scripts/app_store_connect.py`:

```sh
python3 scripts/app_store_connect.py status
python3 scripts/app_store_connect.py invite-tester --email someone@example.com \
    --external --create-group --submit-review --public-link
```

`invite-tester` prints `INVITE …` lines: the tester's Apple `state`
(`INVITED`/`ACCEPTED`/`INSTALLED` means the invite is live; `NOT_INVITED`/
`REVOKED` is not), the build's `externalBuildState`, and `INVITE public_link=…`
when a public TestFlight link is available. External testers can only *install*
once the build's `externalBuildState` is `BETA_APPROVED` / `READY_FOR_BETA_TESTING`
/ `IN_BETA_TESTING`; before that the invite is queued behind Beta App Review.
Pass `--internal` to invite onto the internal group instead — that requires the
email to be an App Store Connect user, so it reports a blocker rather than
silently promoting anyone to a Marketing seat.

Doing it by hand in App Store Connect instead:

1. TestFlight → **External Testing** → new group.
2. Add the build. Fill **What to Test**, contact email, and the review notes below.
3. Submit for Beta App Review. There is no login; say so.
4. When approved, add testers by email or a public link.

## What to Test

Paste this into the TestFlight group:

```
iPhone or iPad on iOS/iPadOS 18. The keyboard adapts: a compact single-column board on iPhone, the larger multi-column board on iPad.

1. Open access: keyboard. Type on the Type screen. On iPad the layout matches a normal iPad keyboard, including the globe key, with keys larger than a stock board; on iPhone it is the compact board sized to the phone. Letters should use the literacy font. Double-space should insert a full stop. Hold delete to remove letters, then words. Two fingers on the keyboard should move the cursor.
2. Settings → Colours → Coloured vowels. Vowels, consonants, numbers, and punctuation take their colours. Shift and Caps Lock should show capitals. Type a few misspellings and tap Fix on the suggestion bar. The first Fix asks before sending the field; Allow sends it, Not now does not. Undo should restore the original. Password fields must not send text. With Full Access off, typing still works and Fix explains that it needs Full Access.
3. Settings → General → Keyboard → Keyboards → Add New Keyboard… → access: keyboard. Open that keyboard and enable Allow Full Access.
4. In Notes or Safari, switch to access: keyboard with the globe key. Colour settings and Fix should now work there too.
5. VoiceOver: every key should have a spoken label (Shift, Delete, Next Keyboard, and so on).

The keyboard still types with Full Access off. Full Access shares colour settings and on-device learned words, and lets Fix reach https://access-keyboard.vercel.app/api/fix. Keystrokes stay on the device. Fix sends only the current field, and only after you tap Allow.
```

## Beta review notes

Paste this into the Beta App Review notes:

```
This is an assistive keyboard for iPhone and iPad. There is no account or login.

The keyboard will not appear in other apps until the reviewer adds it:
Settings → General → Keyboard → Keyboards → Add New Keyboard… → access: keyboard.

The keyboard is fully usable with Allow Full Access turned off and with no network. Typing, layouts, and two-finger cursor movement anywhere on the keyboard do not need either. With Full Access off, Fix does not send text; it shows a short hint, and the keys stay usable.

Full Access is optional and used for two things only:
1. Share colour and layout settings, and on-device learned predictions (PredictionMemory), with the keyboard extension through App Group group.6M3Z27M69P.app.access.keyboard.
2. Let the extension call the Fix proxy at https://access-keyboard.vercel.app/api/fix.

Keystrokes are not sent off the device. Tapping Fix sends the current field’s text only after the reviewer taps Allow. That choice can be turned off in the app’s Settings. The proxy forwards that field to OpenAI with store disabled and does not keep the text. Password fields are skipped. If there is no network, Fix shows a short hint and does not change the field.

The in-app Type screen uses the same keyboard, so layout, colours, and Fix can be tried before enabling the system keyboard.
```

## 4b. Upload from this repo

The App Store Connect `.p8` is not in git. Locally it lives in `secrets/` (see `AppStoreConnect.env.example`). GitHub Actions uses repository secrets.

```sh
sh scripts/upload-testflight.sh
```

That archives Release, bumps `CURRENT_PROJECT_VERSION` past the latest TestFlight build, uploads, waits until Apple marks the build VALID, assigns it to every TestFlight group, and expires every older build. App Store Connect currently requires the iOS 26 SDK, so CI runs on `macos-26`.

Agents start GitHub Actions by pushing a tag (see `AGENTS.md`). Do not claim Actions cannot be started from this environment.

- `testflight-*` archives a new build on `macos-26`, then runs `latest-only`. Do not do this just to fix testers; repeated archives exhaust Apple Development certificates.
- `sync-testflight-*` runs `latest-only` on Ubuntu only. Use it to reinvite testers onto the live build.

```sh
git tag sync-testflight-<short-reason>
git push origin sync-testflight-<short-reason>
```

**Actions → TestFlight → Run workflow** is the same as `sync-testflight-*`. It always gives every tester the latest existing build. It does not ask.

## After the first build

- Each new upload needs a new `CURRENT_PROJECT_VERSION` on the app **and** the extension.
- Keep `MARKETING_VERSION` at `0.1.0` until you intend a user-visible version change.
- Testers only ever get the latest build. Uploads and **Run workflow** expire every older one.
- A tester who still sees an old build and “No TestFlight builds are available” is `REVOKED` or `NOT_INVITED`. Delete them and send a new EMAIL invite. Do not expire older builds until every emailed tester is `INVITED`, `ACCEPTED`, or `INSTALLED`.
- If Fix starts failing for testers, check the Vercel deployment, `OPENAI_API_KEY`, and `FIX_PROXY_SECRET` on that project. A 401 means the app secret and the Vercel env var do not match.
