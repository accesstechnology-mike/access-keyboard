# App Store listing draft: access: keyboard

Draft for the first public App Store release. This is not a private or unlisted release. The binary is the universal iPhone and iPad keyboard (`TARGETED_DEVICE_FAMILY = "1,2"`, iOS and iPadOS 18). Do not treat this file as already entered in App Store Connect.

Fix ships in v1. `FeatureFlags.fixConsentRequired` is **on**, so the first Fix asks Allow / Not now before any text is sent.

Source for the review notes and privacy answers: `TESTFLIGHT.md`.

## Pricing (confirmed by Mike, 19 Oct 2026)

| | |
| --- | --- |
| Keyboard and predictions | Free, for good. Nothing locks without Pro. |
| Fix, free | 30 Fixes per calendar month, counted by the Fix service per App Store install (`appTransactionId`) |
| Pro Monthly | £3.99 a month, 14-day free trial |
| Pro Yearly | £29.99 a year, 14-day free trial |
| Pro Lifetime | £79.99 once, non-consumable, no trial |
| Pro fair use | Up to 100 Fixes a day |

The app never hard-codes prices or trial wording. The paywall uses StoreKit `displayPrice` and the introductory offer StoreKit returns. The limits live in `SubscriptionConfig` (app copy) and in the Fix service env vars (enforcement; see `proxy/README.md`).

## TODO: Mike in App Store Connect

- **Paid Apps agreement, banking and tax.** In-app purchases cannot be submitted until the Paid Apps agreement is active and banking and tax are complete.
- **Products.** `scripts/asc_create_products.py` creates them. It is a dry run unless run with `--apply`; nothing has been created yet. It makes:
  - Subscription group `access: keyboard Pro`.
  - `app.access.keyboard.6M3Z27M69P.pro.yearly` (£29.99, level 1) and `app.access.keyboard.6M3Z27M69P.pro.monthly` (£3.99, level 2), each with a 14-day free trial.
  - Non-consumable `app.access.keyboard.6M3Z27M69P.pro.lifetime` (£79.99).
  - UK base prices, equalised elsewhere, available in all territories, en-GB and en-US names.
- **Review screenshots.** Each product needs a screenshot of the paywall before it can be submitted. The script does not upload one.
- **Free access for chosen people.** Use offer codes in App Store Connect once the app is Ready for Distribution and the products are approved. The app has a Redeem Code button on the Pro screen and in Settings.
- **Fix service.** Add an Upstash Redis (or Vercel KV) database to the Vercel project before release, so the 30 a month and 100 a day limits are enforced. Without it, Fix works but is not counted.
- **Privacy page deploy.** The source is `proxy/public/privacy.html`. App Store Connect should use `https://access-keyboard.vercel.app/privacy.html`. The live page updates when the Vercel project deploys from `main`. Confirm the deployed page matches this repo before review.
- **Support URL.** Proposed below from the company site. Confirm or replace it before submission.

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
| Version | `1.0` (marketing version in the Xcode project; matches the App Store Connect version record) |
| Price | Free. In-app purchases: Pro Monthly £3.99, Pro Yearly £29.99 (both with a 14-day free trial), Pro Lifetime £79.99. |

Subtitle is 27 characters (limit 30). Name is 16 characters (limit 30). Promotional text is under 170 characters. Keywords are 79 characters (limit 100).

## Promotional text

170 characters maximum.

```
A free assistive keyboard for iPhone and iPad, with large keys and a literacy font. Fix corrects your typing: 30 free a month, or more with Pro.
```

## Description

```
access: keyboard is a free assistive keyboard for iPhone and iPad. It starts from the layout you already know and keeps the keys large.

It works on iOS and iPadOS 18. iPhone gets a compact board. iPad and iPad Pro get larger boards. QWERTY is the starting layout. ABC order and a frequency grid are optional. Coloured vowels, Beth colours and high-contrast themes are optional. The keys use a literacy font.

Move the cursor with two fingers anywhere on the keyboard, as on the system keyboard. Hold delete to remove letters, then words. Tap space twice for a full stop. Hold a letter for accents. VoiceOver reads each key.

Predictions learn the words you use. That learning stays on your device.

The keyboard and predictions are free, for good.

Fix corrects spelling and grammar in the paragraph you are typing in. It is free for 30 Fixes a month. Pro gives you up to 100 Fixes a day. Pro is monthly or yearly, each with a 14-day free trial, or a single Lifetime payment.

How Fix works: when you tap Fix, that paragraph is sent to an AI service (OpenAI) through our server to be corrected. Each Fix costs us money, which is why it has limits and Pro is paid. Nothing is sent until you tap Fix, and the first time you are asked to allow it. Our server does not keep your text. Keystrokes are not sent. Password fields are skipped.

To use it in other apps: Settings > General > Keyboard > Keyboards > Add New Keyboard > access: keyboard.
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

The privacy page describes the free keyboard, on-device predictions, what Fix sends to OpenAI and when, the signed Apple records used to count Fixes, and the contact address. There was no separate support address elsewhere in the repo.

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

The keyboard does not browse the web, host a social feed, or show ads. Fix sends the current paragraph to OpenAI only after the user taps Fix and Allow; that is app functionality, not unrestricted web access and not content shared with other users. Confirm the labels against the live App Store Connect form if Apple has renamed a row.

## Privacy nutrition label

Tracking: **No**.

| Question | Answer |
| --- | --- |
| Other User Content | Collected, for App Functionality, not linked, not tracking. The paragraph being corrected, only when the user taps Fix, after Allow. |
| Purchases (Purchase History) | **Decision for Mike.** Each Fix now sends Apple-signed StoreKit data (app transaction, and the Pro transaction if any) so the Fix service can count use. The service keeps a count keyed by `appTransactionId` or `originalTransactionId` for up to 32 days. That most likely means declaring Purchase History, App Functionality, not tracking. Whether it is "linked" needs Mike's call. The privacy manifests (`PrivacyInfo.xcprivacy`) do not declare it yet. |
| Third party | Yes. `https://access-keyboard.vercel.app/api/fix` forwards the paragraph to OpenAI with `store` disabled. The service does not keep the text. Ordinary keystrokes stay on the device. Password fields are skipped. |
| Colour settings and learned predictions | On-device only (App Group `group.6M3Z27M69P.app.access.keyboard` and UserDefaults). Not collected. |
| Payment | Handled by Apple. Not collected by the app. |

## App Review notes

Paste this into App Review.

```
access: keyboard is an assistive keyboard for iPhone and iPad. There is no account or login.

The keyboard and predictions are free and never lock. The only paid part is Fix, which sends the paragraph being typed to an AI service (OpenAI) through our server to correct it. Fix is free for 30 uses a month. Pro allows up to 100 a day.

In-app purchases (Pro screen in the app, and Settings > Pro):
- app.access.keyboard.6M3Z27M69P.pro.monthly: auto-renewing, 1 month, 14-day free trial
- app.access.keyboard.6M3Z27M69P.pro.yearly: auto-renewing, 1 year, 14-day free trial
- app.access.keyboard.6M3Z27M69P.pro.lifetime: non-consumable, one payment
Prices and trial wording come from StoreKit. The Pro screen has Restore Purchases, Redeem Code, Manage Subscriptions, the Privacy Policy (https://access-keyboard.vercel.app/privacy.html) and Terms of Use (https://www.apple.com/legal/internet-services/itunes/dev/stdeula/).

To try it: open the app and use the Type screen. Tap Fix and choose Allow. To buy, open Pro and use a Sandbox account.

To use the keyboard in other apps:
Settings > General > Keyboard > Keyboards > Add New Keyboard > access: keyboard. Then turn on Allow Full Access if you want Fix and shared settings. The keyboard types with Full Access off.

Full Access is used to:
1. Share colour and layout settings, and on-device learned predictions, between the app and the keyboard through App Group group.6M3Z27M69P.app.access.keyboard.
2. Let the keyboard read the Apple-signed purchase records the app saves there, and call the Fix service at https://access-keyboard.vercel.app/api/fix.

Keystrokes are not sent off the device. Fix sends only the current paragraph, only after the user taps Fix and Allow. Permission can be taken back in Settings (Allow Fix to send text). Fix also sends Apple-signed StoreKit records so our server can count Fixes; it checks Apple's signature and keeps only a count. If the free Fixes for the month are used up, the keyboard shows a short message and carries on typing. With no network, Fix shows a short hint and does not change the text.
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
| `SubscriptionConfig.monetization` | `.keyboardFreeFixAllowance` (keyboard free, Fix limited by the service) | `Packages/AccessKeyboardCore/Sources/AccessKeyboardCore/SubscriptionConfig.swift` |
| `SubscriptionConfig.showTrialHeadlineDefault` | on | same file; remote `config.json` can hide the headline only |

Beth mode is listed in Settings under the name Beth. `BethColorMap` supplies the colours.
