# Menu Bar Popup & Mini Capsule Redesign

## Summary

Remove the TranscriptionMode preset system entirely. Redesign the menu bar popup to be minimal (status + hotkey + Settings + Quit). Redesign the mini capsule to be more cohesive with the large overlay.

## Scope of Changes

### Remove
- `TranscriptionMode.swift` — delete file
- All references to `currentMode`, `setMode`, `TranscriptionMode` across AppState, MenuBarView, SettingsView, RecordingView, TranscriptionResult

### Menu Bar Popup

Width 220pt, native macOS material background.

```
● Ready / Loading... / Recording...   ← colored dot + status text
⌥ Droite                              ← current hotkey, secondary color

────────────────────────────────────

Settings                              ← plain button, full width
Quit                                  ← plain button, full width, red tint
```

- Dot color: green = ready, orange = loading, red = recording
- Hotkey reads dynamically from `UserDefaults` key `triggerKey`
- No mode selector, no last transcription, no record button

### Mini Capsule

Size: 72×28pt, always visible.

| State       | Content                          |
|-------------|----------------------------------|
| Idle        | `mic.fill` SF Symbol, white 0.4 opacity |
| Recording   | FFT thin white bars (same as large overlay) |
| Transcribing | Pulsing dots (same as large overlay) |

- Black background capsule
- Smooth `.easeInOut(duration: 0.2)` transitions between states
- Same visual language as large overlay (black, white, no color)

## Files to Modify

- `TranscriptionMode.swift` → delete
- `AppState.swift` → remove `currentMode`, `setMode`
- `MenuBarView.swift` → full rewrite
- `SettingsView.swift` → remove Modes tab + TranscriptionMode references
- `RecordingView.swift` → remove mode references
- `TranscriptionResult.swift` → remove `mode` field
- `AppDelegate.swift` → mini capsule idle state (mic icon)
