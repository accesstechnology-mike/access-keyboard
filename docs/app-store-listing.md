# App Store listing draft — access: keyboard

Draft for the first public App Store release. This is not a private or unlisted release. The binary is the universal iPhone + iPad keyboard (`TARGETED_DEVICE_FAMILY = "1,2"`, iOS/iPadOS 18). Latest TestFlight upload is build 18. Do not treat this file as already entered in App Store Connect.

Fix ships in v1. `FeatureFlags.fixConsentRequired` is **on**, so the first Fix tap asks Allow / Not now before any text is sent.

Source for the review notes and privacy answers: `TESTFLIGHT.md`.

## TODO — Mike in App Store Connect

The app price and the product IDs are decided. Mike still has to create the subscription in App Store Connect before review. The app does not hardcode prices and does not grant Pro from config.

- **Paid Apps agreement, banking, and tax.** A subscription cannot be submitted until the Paid Apps agreement is active and banking and tax are complete.
- **Subscription group.** One group, name `access: keyboard Pro`.
- **Products.** Create exactly `app.access.keyboard.6M3Z27M69P.pro.monthly` at £1.99 per month and `app.access.keyboard.6M3Z27M69P.pro.yearly` at £19.99 per year. Those IDs are `SubscriptionConfig` in `Packages/AccessKeyboardCore/Sources/AccessKeyboardCore/SubscriptionConfig.swift`.
- **Introductory offer.** The trial length is chosen here, not in the app. Pick 7 or 14 days (still TBD) as a free introductory offer on the products. The paywall shows that offer only when StoreKit returns it and the user is eligible.
- **Subscription review screenshot.** Apple asks for a screenshot of the paywall (the Pro screen) when the subscription is submitted.
- **Privacy page deploy.** The page source is `proxy/public/privacy.html`. App Store Connect should use `https://access-keyboard.vercel.app/privacy.html`, which serves that file. The live URL updates when the Vercel project deploys from `main`. Confirm the deployed page matches this repo before review. `proxy/public/config.json` is the optional paywall headline switch at `https://access-keyboard.vercel.app/config.json`.
- **Support URL.** Proposed below from the company site already referenced in the repo (`scripts/generate-icon.swift`). Confirm it, or replace it, before submission.

## Identity

| Field | Value |
| --- | --- |
| Name | `access: keyboard` |
| Subtitle | `Large keys, iPhone and iPad` |
| Bundle ID | `app.access.keyboard.6M3Z27M69P` |
| SKU | `app.access.keyboard.6M3Z27M69P` |
| Primary category | Utilities |
| Secondary category | Productivity (optional) |
| Primary language | English (UK), unless the App Store Connect record is already English (US). The keyboard’s `PrimaryLanguage` is `en-US`. |
| Copyright | Access Technology North Limited |
| Version | `0.1.0` (marketing version in the Xcode project) |
| Price | Free download. Pro is an auto-renewing subscription: £1.99 a month or £19.99 a year, entered in App Store Connect. The paywall shows StoreKit’s localized price. |

Subtitle is 27 characters (limit 30). Name is 16 characters (limit 30). Promotional text is 154 characters (limit 170). Keywords are 79 characters (limit 100).

## Promotional text

170 characters maximum. This draft is within that limit.

```
An assistive keyboard for iPhone and iPad. Large keys and a literacy font stay free. Pro adds Fix, which can correct the current field after you allow it.
```

Fix ships in this version, behind Pro, with the consent step on.

## Description

```
access: keyboard is an assistive keyboard for iPhone and iPad. It starts from the layout you already know and keeps the keys large.

It runs on iPhone and iPad on iOS and iPadOS 18. The same app lays out a compact board on iPhone and the larger iPad and iPad Pro boards. QWERTY is the starting layout. ABC order and a frequency grid are optional. Coloured vowels, Beth colours, and high-contrast themes are optional. A literacy font is used on the keys.

Two fingers anywhere on the keyboard move the cursor, as on the system keyboard. Hold delete to remove letters, then words. Double-space inserts a full stop. Long-press a letter for accents. VoiceOver speaks each key.

The suggestion bar can learn words you type. That learning stays on the device (PredictionMemory in the app’s shared App Group when Full Access is on). It is not uploaded.

The keyboard works without a subscription. Fix is part of Pro, an auto-renewing subscription (monthly or yearly) purchased in this app through Apple. Tapping Fix can correct the text in the current field. Nothing is sent until you tap Fix, and this version asks you to Allow it once before the first send. You can turn that off in Settings. Only that field is sent, to OpenAI through access: keyboard’s server, so it can be corrected. The server does not keep the text. Ordinary keystrokes are not sent. Password fields are skipped. With no network, or without Pro, Fix does not send anything and the keyboard keeps typing.

You can type with Allow Full Access turned off. Full Access is only for sharing colour, layout, and learned words with the keyboard in other apps, and for letting Fix reach the network. The app includes a Type screen so you can try the keyboard before enabling it system-wide.

To use it in other apps: Settings → General → Keyboard → Keyboards → Add New Keyboard… → access: keyboard.
```

## Keywords

100 characters maximum, comma-separated. The app name already contains “access” and “keyboard”, so those words are left out.

```
assistive,accessibility,AAC,eye gaze,literacy,large keys,switch,contrast,typing
```

## URLs

| Field | Value |
| --- | --- |
| Support URL | `https://www.accesstechnology.co.uk` |
| Marketing URL | Leave blank unless Mike wants the company site here too |
| Privacy Policy URL | `https://access-keyboard.vercel.app/privacy.html` |
| Contact | `mike@accesstechnology.co.uk` |

The privacy page describes an iPhone and iPad keyboard, on-device PredictionMemory, what Fix sends to OpenAI and when, and that contact address. There was no separate support address elsewhere in the repo.

## Age rating

Answer **None** or **No** to every content and capability question. Expected result: **4+**.

| Question | Answer |
| --- | --- |
| Cartoon or fantasy violence | None |
| Realistic violence | None |
| Guns or other weapons | None |
| Sexual content or nudity | None |
| Profanity or crude humor | None |
| Alcohol, tobacco, or drug use | None |
| Mature or suggestive themes | None |
| Horror or fear | None |
| Medical or treatment information | None |
| Gambling or contests | None |
| Unrestricted web access | No |
| User-generated content shared with other users | No |
| Messaging or chat | No |
| Advertising | No |

The keyboard does not browse the web, host a social feed, or show ads. Fix sends the current field to OpenAI only after the user taps Fix and Allow; that is app functionality, not unrestricted web access and not content shared with other users. Confirm the labels against the live App Store Connect form if Apple has renamed a row.

## Privacy nutrition label

Tracking: **No**.

Fix ships in v1, with the consent step on:

| Question | Answer |
| --- | --- |
| Data collected | Other User Content (the current text field) |
| Linked to the user’s identity | No |
| Used for tracking | No |
| Purpose | App Functionality |
| When | Only if the user taps Fix, and only after they tap Allow while consent is required |
| Third party | Yes. `https://access-keyboard.vercel.app/api/fix` forwards that field to OpenAI with `store` disabled. The proxy does not keep the text. Ordinary keystrokes stay on the device. Password fields are skipped. |
| Colour settings and learned predictions | On-device only (App Group `group.6M3Z27M69P.app.access.keyboard` and UserDefaults). Not collected. |
| Purchases | Handled by Apple. Payment details are not collected by the app. Pro status (active, product, expiry) stays on the device in that App Group. |

The privacy manifests already declare UserDefaults (`CA92.1`) and Other User Content for app functionality, not linked, not tracking.

## App Review notes

Paste this into App Review. It matches `TESTFLIGHT.md` and Guideline 4.4.1: the keyboard is fully usable with Full Access off and with no network. Full Access is optional and is justified below.

```
This is an assistive keyboard for iPhone and iPad. There is no account or login.

The keyboard will not appear in other apps until the reviewer adds it:
Settings → General → Keyboard → Keyboards → Add New Keyboard… → access: keyboard.

The keyboard is fully usable with Allow Full Access turned off and with no network. Typing, layouts, and two-finger cursor movement anywhere on the keyboard do not need either. With Full Access off, Fix does not send text; it shows a short hint, and the keys stay usable.

Full Access is optional and used for two things only:
1. Share colour and layout settings, and on-device learned predictions (PredictionMemory), with the keyboard extension through App Group group.6M3Z27M69P.app.access.keyboard.
2. Let the extension call the Fix proxy at https://access-keyboard.vercel.app/api/fix.

Keystrokes are not sent off the device. Tapping Fix sends the current field’s text only after the reviewer taps Allow. That choice can be turned off in the app’s Settings (Allow Fix to send text). The proxy forwards that field to OpenAI with store disabled and does not keep the text. Password fields are skipped. If there is no network, Fix shows a short hint and does not change the field.

The in-app Type screen uses the same keyboard, so layout and colours can be tried before enabling the system keyboard.

Subscription group: access: keyboard Pro.
Products: app.access.keyboard.6M3Z27M69P.pro.monthly (£1.99 per month) and app.access.keyboard.6M3Z27M69P.pro.yearly (£19.99 per year). Both auto-renew until cancelled.
Introductory offer: the trial length is set in App Store Connect (7 or 14 days, still TBD). The app shows trial wording only when StoreKit reports an offer and the account is eligible. Config cannot grant access.
Paywall: open the app and choose Pro. It lists both plans with the price, period, and renewal terms from StoreKit, plus auto-renew wording, Manage Subscriptions, Restore Purchases, the Privacy Policy (https://access-keyboard.vercel.app/privacy.html), and Terms of Use (https://www.apple.com/legal/internet-services/itunes/dev/stdeula/).
The containing app verifies Transaction.currentEntitlements, listens to Transaction.updates, finishes transactions, and writes active, product, and expiry into App Group group.6M3Z27M69P.app.access.keyboard. It refreshes that record on launch and when the app returns to the foreground. The keyboard only reads the record. A missing or expired record means not subscribed. The keyboard never shows a purchase screen. A non-subscriber who taps Fix sees a short message to open the app to subscribe. Consent (Allow / Not now) is asked only after that entitlement check, and only when Pro is active.
Sandbox path: sign in with a Sandbox Apple ID, open Pro, buy either plan, then tap Fix on the Type screen and choose Allow. Restore Purchases is on the same screen. In another app, add the keyboard and turn on Allow Full Access so it can read the App Group record. Without a subscription, Fix shows the subscribe message and does not send text.

Demo: open the app, type on the Type screen. Open Pro and subscribe in the sandbox, then try Fix and choose Allow. To review the system keyboard, add it in Settings as above. Full Access can stay off; the keys still work.
```

## App Review information

| Field | Value |
| --- | --- |
| Sign-in required | No |
| Contact | `mike@accesstechnology.co.uk` |
| Notes | The block above |
| Devices | iPhone and iPad. If the App Store Connect record was created as iPad-only, an admin must turn on iPhone availability. The binary is already universal. |

## Export compliance

`ITSAppUsesNonExemptEncryption = NO`. If App Store Connect asks: **No**, the app does not use non-exempt encryption. Fix uses the system HTTPS stack.

## Feature flags the reviewer will hit

| Flag | Default | Where |
| --- | --- | --- |
| `FeatureFlags.fixConsentRequired` | on | `Packages/AccessKeyboardCore/Sources/AccessKeyboardCore/FeatureFlags.swift` |

Beth mode is listed in Settings under the name Beth. `BethColorMap` supplies the colours.
