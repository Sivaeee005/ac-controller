# Testing

There are two kinds of results. Never mix them up.

| Kind | Where | What it proves |
|---|---|---|
| **Simulated** | `flutter test` (CI) and `ac-controller-SIMULATED.apk` | The app logic: confirmation, retry, reconnect, UI |
| **Real AC** | `ac-controller-matter.apk` on your phone, with the Panasonic AC | That the app really controls your AC |

## Stage 1 — real AC checklist

Before you start:
- The AC is powered (breaker ON) and in **setup mode**: hold the **SMART**
  button on the AC remote for 5 seconds until the AC display shows a blinking
  Wi-Fi icon and "SE". This is Panasonic's instruction, taken from the MirAIe app.
- Your phone is on the **2.4 GHz** home Wi-Fi, with Bluetooth ON.
- You have the 11-digit code from the Matter sticker. Do not share it.

Install `ac-controller-matter.apk` (allow "Install unknown apps" for your
file manager or browser). Then record the result of each step:

| # | Test | Steps | Expected | Result (Pass/Fail + notes) |
|---|---|---|---|---|
| 1 | Pairing | Enter the setup code, Wi-Fi name and password → **Pair AC** | Progress steps, then the device screen shows **Connected** | |
| 1a | Certificate check | If a "Certificate check failed" dialog appears, note the code | Note the code | |
| 2 | State read | Look at "Reported by the AC" | Values shown; room temperature may be "Not reported" | |
| 3 | Power ON | Tap the power button | "Power ON: confirmed by the AC"; the AC really starts | |
| 4 | Power OFF | Tap again | "Power OFF: confirmed by the AC"; the AC really stops | |
| 5 | IR remote sync | Turn the AC on/off with the IR remote | The app updates within a few seconds | |
| 6 | Connection loss | Turn phone Wi-Fi off for 30 s, then on | "Not connected", then back to "Connected" by itself or with Retry | |
| 7 | AC power loss | Switch the AC breaker off for 1 min, then on | "Not connected", then "Connected" again | |
| 8 | App restart | Close the app fully, open it again | Connects again without pairing | |
| 9 | Capability report | Tap **Copy report** and send it | The report text | |

If something fails, send the step number, the exact message on screen and a
screenshot. If you can, also capture a log: on a PC with ADB, run
`adb logcat -s MatterBridge BleConnector PaaTrustStore chip.*`. Check the log
for Wi-Fi details before sharing it.

## Stage 1 — real AC results

| Date | Build | Step | Result | Notes |
|---|---|---|---|---|
| 2026-10-24 | run 40095973855 | 1 Pairing | **Fail** | "AC was not found over Bluetooth". Cause found in the app: the BLE scan used the short discriminator from the manual code without converting it to the 12-bit form, so it could never match. Fixed in the next build; the AC must also be in setup mode (SMART button, 5 s). |

## Stage 1 — simulated results

Run in CI on every push (`flutter test`): 27 tests covering confirmed
commands, "not confirmed" when no report arrives, failure and retry,
not-connected errors, unsupported modes, temperature limits, IR-remote
changes, ordered commands, reconnect with capped backoff, pairing progress,
removal, password field hiding, and "Not reported" for missing values.
