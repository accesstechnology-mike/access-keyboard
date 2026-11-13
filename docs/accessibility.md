# Accessibility, 1.0.1

Checked from the source. Not run on an iPhone or iPad. Do not tick an App Store accessibility nutrition label from this file alone until the “device pass” line for that label has been done.

The nutrition labels Apple shows are: VoiceOver, Voice Control, Larger Text, Dark Interface, Differentiate Without Color Alone, Sufficient Contrast, Reduced Motion, Captions, Audio Descriptions.

## What this release changes

- Letter keys and iPad prediction cells implement `accessibilityActivate`. `UIControl` does not do that on its own, so VoiceOver and Switch Control were not inserting a letter or choosing a prediction. Delete activates once and does not auto-repeat.
- A letter’s accents are VoiceOver custom actions, so a long-press is not the only way to reach them.
- The About screen says so.

## Labels

| Label | Claim? | Why |
| --- | --- | --- |
| VoiceOver | After a device pass | Keys, predictions, Fix, Allow / Not now, and the host app screens have spoken labels. Fix hints are posted as announcements. Activation is implemented in this release. Still untested with VoiceOver running: focus order on the iPad column, the two-finger cursor pan (VoiceOver uses its own gestures), and whether the accent actions rotor is practical. |
| Voice Control | After a device pass | The same labels are what Voice Control speaks (“tap a”, “tap Fix”). Not exercised here. |
| Larger Text | No | The host app uses Dynamic Type (the Type field, its caption, and the SwiftUI screens). The keyboard does not. Letter sizes are fixed (24 pt on iPhone, 28 pt on iPad, 30 pt on iPad Pro) and do not follow the content-size category. Zoom is not a reason to claim this label. |
| Dark Interface | Yes, after a quick dark-mode pass | The host app uses system colours. The keyboard’s system theme follows the interface style, and Settings offers it. |
| Differentiate Without Color Alone | Yes | Every key has a letter or a symbol. Vowel colours and Beth colours are optional. Shift state changes the letter case as well as the fill. |
| Sufficient Contrast | Yes for the default and the two hi-contrast themes | System uses the ordinary keyboard palette. Hi-contrast white and hi-contrast yellow are in Settings. Beth colours are a personal palette, not a contrast mode, and were not measured. |
| Reduced Motion | Yes | There is no animated transition on the keyboard. The only motion is the Fix spinner. |
| Captions | No | There is no video or audio-only content. |
| Audio Descriptions | No | There is no video. |

## Other gaps

- Switch Control can activate a focused key now that `accessibilityActivate` inserts it. The accessibility frame is the drawn key, not the larger touch target, so a scan can miss the gap between keys. Item order follows subview order. This was not run with Switch Control.
- Prediction words on iPhone are buttons. On iPad they are custom controls with the same activate path. A hidden cell is `isHidden`, so it drops out of the accessibility tree.
- Password fields are skipped by Fix. The keys themselves are still readable by VoiceOver, which is the same as the system keyboard.

## What Keeble has, and what it would take

Keeble (Keeble Assistive Keyboard) is aimed at eye-gaze and switch users. Three of its features are not in access: keyboard. This is a scope note, not a design to build in 1.0.1.

### Dwell selection

Keeble fills a ring while the pointer rests on a key, then inserts that key after a chosen dwell time.

What already helps: keys are `UIControl`s that type on touch-up. iPadOS Dwell Control, which synthesises a click, can already press them. That is the system feature, not an in-keyboard dwell timer.

What an in-keyboard dwell needs:

- A hover path. `UIHoverGestureRecognizer` on each key sees a pointer. Eye-gaze software that moves the system pointer will hit it. A gaze SDK inside the keyboard extension is not available, and the extension cannot see the camera.
- A per-key timer and a progress ring, cancelled when the pointer leaves. Dwell time belongs in Settings (the host app writes the App Group; the keyboard reads it).
- A rule for accents. Dwell must not also fire the long-press accent callout. One of the two has to win, or accents stay on the VoiceOver actions added in this release.
- Memory. A timer on every key is cheap, but the ring views must be released on a memory warning the same way the accent callout already is. The extension is jetsam-killed around 40–60 MB.

This is a keyboard-extension feature plus one Settings row. It wants a device with a pointer or a gaze driver before it is called done.

### Select on release

Letters, space, and return already insert in `endTracking` (finger up). Delete inserts on finger down and then repeats. That is the system-keyboard pattern.

Keeble’s switch “select on release” is different: the switch is held to move a scan, and the item under the highlight is chosen when the switch is released. access: keyboard does not scan. Switch Control’s own item mode is the system version of that, and it depends on the accessibility elements above.

A Keeble-style mode would be a scan of the keys (order, timing, and a switch via Switch Control or a keyboard hardware switch), drawn highlight, and activate-on-release. It is a second input model beside touch, not a one-line change to `endTracking`. Delete would have to wait for release too, or it would type while the person was still holding the switch.

### Speak as you type

Not built. The shape of it:

- `AVSpeechSynthesizer` in the keyboard extension, en-GB voice, speaking each letter or each finished word. A Settings choice, stored in the App Group.
- Interrupt the previous utterance on the next key so speech stays with the cursor.
- Stay silent in password fields, and stay silent when VoiceOver is running so the two do not talk over each other.
- On-device speech. No text leaves the device, so it does not add a privacy-label category.
- Keyboard extensions can speak, but the utterance is ducked and may not play if the host app has taken the audio session. That has to be tried on a device.

Letter mode is a small feature. Word mode needs a definition of a finished word (space, return, or punctuation), which the engine already knows.
