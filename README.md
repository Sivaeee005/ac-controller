# AC Controller

A personal Android app (phone, and later Android TV) that controls a
Panasonic room air conditioner **directly over Matter** on the home Wi-Fi.
No hub, no cloud, no Panasonic account.

- AC: Panasonic CS-SU18BKY3W / CU-SU18BKY3W (Matter certified, vendor 0x0001, product 0x0147)
- Matter SDK: [connectedhomeip](https://github.com/project-chip/connectedhomeip) `v1.4.2.0` (Apache-2.0), built in CI
- UI: Flutter

> Status: **Stage 1 (proof of concept)** — pairing, power ON/OFF with
> confirmation, reported state, and a capability report. Not yet tested on the real AC.

## How it works

```
Flutter UI ──> AcController (confirmed commands) ──> MatterChannelBackend
                                                       │ MethodChannel / EventChannel
                                                       ▼
                                   MatterBridge.kt ──> Matter SDK (CHIPController)
                                                       │ BLE (pairing) / Wi-Fi (control)
                                                       ▼
                                                Panasonic AC (Matter)
```

- The app is its own Matter controller: it creates its own fabric and pairs
  the AC with the setup code from the Matter sticker.
- State comes from a Matter **subscription**: the AC reports changes itself
  (including changes made with the IR remote).
- A command counts as successful **only when the AC's report shows the new
  value**. Otherwise the app shows "not confirmed" or "failed", with Retry.
- Values the AC does not report (for example room temperature) are shown as
  "Not reported". They are never estimated.

## Code layout

| Path | Purpose |
|---|---|
| `lib/src/domain/` | AC state, capabilities, Matter IDs, attribute parser |
| `lib/src/services/ac_controller.dart` | Confirmed commands, reconnect with capped backoff |
| `lib/src/data/matter_channel_backend.dart` | Dart side of the Android Matter bridge |
| `lib/src/data/simulated_backend.dart` | Simulated AC for tests and the SIMULATED demo build |
| `lib/src/ui/` | Screens |
| `android/app/src/main/kotlin/.../matter/` | Matter SDK bridge, Bluetooth pairing, PAA trust store |
| `.github/workflows/build.yml` | Builds the Matter SDK and the APKs |

## Build

GitHub Actions builds everything (see `.github/workflows/build.yml`):

1. The Matter SDK Android libraries for `arm64-v8a` and `armeabi-v7a`, in the
   official `chip-build-android:140` image. Cached after the first build.
2. `flutter analyze` and `flutter test` (simulated AC).
3. `ac-controller-matter.apk` (real AC) and `ac-controller-SIMULATED.apk` (demo).

Download the APKs from the workflow run's **Artifacts** section.

## Tests

`flutter test` runs unit and widget tests against `SimulatedBackend`.
These are **simulated** results. Tests on the real AC are recorded separately.

## Security

- No secrets in this repository: no setup codes, Wi-Fi passwords, tokens or keys.
- The Wi-Fi password is typed in the app, sent only to the AC during pairing,
  and never stored.
- Device attestation uses the public CSA production PAA root certificates.
  If verification fails, the app asks before continuing.
- The release APK is signed with a debug key. It is for personal use only and
  must not be published.

## Licences

The Matter SDK and the adapted `BleConnector.kt` are Apache-2.0
(© Project CHIP Authors).
