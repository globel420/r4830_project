# R4830 Flutter Functional Freeze Checklist

This is the line-by-line execution plan to finish functionality before UI redesign.

## Ground Rules

- Do not use OEM unless a checklist item fails or is marked OEM-critical.
- Password behavior is safety-critical: if anything is ambiguous, stop and verify in OEM.
- Every step requires both:
  - Flutter app save/action result (including Save Tracking/ACK where applicable)
  - Real charger behavior and/or telemetry confirmation

## Run Setup

- Launch app:
  - `cd /Users/globel/r4830_project/swift && /Users/globel/flutter/bin/flutter run -d macos`
- Keep Live screen open for RX/TX + Hub screen for setting saves.
- Keep Save Tracking visible while testing.

## Line-By-Line Checklist

Status keys: `[ ]` pending, `[x]` complete, `[!]` blocked/fallback needed.

### Batch A: No Active Charging / No Wheel Required

| ID | Status | Test Step | Pass Criteria | Est. Time |
|---:|:---:|---|---|---:|
| 01 | [ ] | Launch app + connect BLE + discover RX/TX | Connected, RX subscribed, no connect errors | 10 min |
| 03 | [ ] | Keepalive/poll sanity | Keepalive on/off does not break RX/TX | 5 min |
| 07 | [ ] | Power-On Output State (`0x0B`) Open/Close | ACK both ways; semantics confirmed on reconnect | 8 min |
| 08 | [ ] | Auto Stop (Full) (`0x14`) | ACK both ways; setting reflected in telemetry/UI | 6 min |
| 10 | [ ] | Two-Stage Charging (`0x20`) | ACK both ways; state/readback confirmed | 6 min |
| 11 | [ ] | Stage 2 Voltage (`0x21`) | ACK and readback value match | 6 min |
| 12 | [ ] | Stage 2 Current (`0x22`) | ACK and readback value match | 6 min |
| 13 | [ ] | Manual Output Control (`0x23`) | ACK both ways; state/readback confirmed | 6 min |
| 14 | [ ] | Soft Start Time (`0x26`) | ACK and readback value match | 6 min |
| 15 | [ ] | Power Limit (`0x27`) | ACK and readback value match | 6 min |
| 17 | [ ] | Multi-Motor Mode (`0x2F`) | Intelligent/Equal both ACK + reflected state | 6 min |
| 18 | [ ] | Language: English (`0x2A`) | ACK and reflected state | 4 min |
| 19 | [ ] | Language: Chinese Simplified (`0x2A`) | ACK and reflected state | 4 min |
| 20 | [ ] | Language: Chinese Traditional (`0x2A`, candidate) | ACK and reflected state; if fail, mark OEM fallback | 6 min |
| 21 | [ ] | Device Name (`0x1E`) | Save works, reconnect, name persists | 8 min |
| 22 | [ ] | Password set test (temporary) (`0x1B`) | Set temp password, reconnect/auth works, no lockout | 12 min |
| 23 | [ ] | Password rollback test | Change back to safe/known password; verify reconnect/auth | 12 min |
| 24 | [ ] | Wrong-password negative test | Wrong password fails as expected; known password still works | 8 min |
| 26 | [ ] | Final software gate | `flutter analyze` + `flutter test` both pass | 12 min |
| 27 | [ ] | Freeze decision | No P0 unknowns remain; document any residual candidates | 5 min |

Batch A subtotal: about **2h 20m**.

### Batch B: Active Charging / Wheel Required

| ID | Status | Test Step | Pass Criteria | Est. Time |
|---:|:---:|---|---|---:|
| 02 | [ ] | Baseline RX health under charge | RX count increases while charger is actively charging | 5 min |
| 04 | [ ] | Output Voltage Setpoint (`0x07`) under load | ACK + under-load behavior/telemetry match | 6 min |
| 05 | [ ] | Output Current Limit (`0x08`) under load | ACK + under-load behavior/telemetry match | 6 min |
| 06 | [ ] | Output Enable (`0x0C`) ON/OFF under load | Both directions ACK, charger behavior matches | 8 min |
| 09 | [ ] | Power-Off Current (`0x15`) threshold behavior | ACK + behavior at chosen threshold values | 8 min |
| 16 | [ ] | Charge Statistics Reset (`0x13`) | Command accepted and reset effect observed in active session | 5 min |
| 25 | [ ] | Reconnect/stability soak while charging | 10+ minute run, repeated saves, no RX/TX desync | 20 min |

Batch B subtotal: about **1h 00m**.

### Suggested Execution Order

1. Finish Batch A first while wheel is not present.
2. Bring wheel in once and complete Batch B in one charging session.
3. If any Batch B item fails, stop and mark `[!]`, then decide whether OEM fallback is needed.

## Time Estimate

- Batch A (no wheel): about **2h 20m**.
- Batch B (wheel/active charging): about **1h 00m**.
- Best-case total (no blockers): about **3.5 to 4.5 hours**.
- Realistic with 1-2 retries: about **5 to 6 hours**.
- If password or language candidate fails and OEM fallback is needed: add **60 to 120 minutes**.

## OEM Fallback Triggers (Only If Needed)

- Password set/auth behavior is inconsistent or lockout risk appears.
- Traditional Chinese payload does not ACK or does not apply correctly.
- Any mapped command repeatedly returns `REJECTED`/`NO_ACK` despite good RX link.

## Definition of Done (Functionality)

- All non-password items verified on real hardware.
- Password flow verified end-to-end safely (set, reconnect/auth, rollback).
- No critical blockers in Save Tracking.
- Analyzer/tests green.
- Candidate mappings either confirmed or explicitly documented as pending.
