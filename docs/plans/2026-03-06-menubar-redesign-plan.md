# Menu Bar Redesign Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Remove TranscriptionMode preset system, redesign menu bar popup (status + hotkey + Settings + Quit), redesign mini capsule (mic icon at rest, bars when recording).

**Architecture:** 4 independent tasks executed in order. Start by re-applying the stash which contains the thin-bar FFT work. Each task builds on the previous. No new dependencies.

**Tech Stack:** Swift, SwiftUI, AppKit, AVFoundation

---

### Task 0: Re-apply stash

The git stash contains valid in-progress work (thin FFT bars, external screen fix, WhisperService optimization, Settings dock icon). Apply it before touching anything.

**Step 1: Apply stash**
```bash
git stash pop
```
Expected: conflicts unlikely, all changes in different sections.

**Step 2: Build to verify**
```bash
xcodebuild -project BetterFasterWhisper.xcodeproj -scheme BetterFasterWhisper -configuration Debug build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

---

### Task 1: Remove TranscriptionMode system

**Files:**
- Delete: `App/BetterFasterWhisper/Sources/Core/Models/TranscriptionMode.swift`
- Modify: `App/BetterFasterWhisper/Sources/Core/Models/AppState.swift`
- Modify: `App/BetterFasterWhisper/Sources/Core/Models/TranscriptionResult.swift`
- Modify: `App/BetterFasterWhisper/Sources/UI/Screens/RecordingView.swift`

**Step 1: Remove `currentMode` and `setMode` from AppState.swift**

Find and delete these two lines (around line 41 and 329):
```swift
@Published var currentMode: TranscriptionMode = .voice
```
```swift
func setMode(_ mode: TranscriptionMode) {
    currentMode = mode
}
```

**Step 2: Remove `mode` from TranscriptionResult.swift**

Remove the `mode` field, parameter, and assignment:
- Delete: `let mode: TranscriptionMode` (line 51)
- Delete: `mode: TranscriptionMode = .voice` from init parameters (line 61)
- Delete: `self.mode = mode` from init body (line 70)

**Step 3: Remove mode indicator from RecordingView.swift**

Delete the HStack block (lines 54-61):
```swift
// Mode indicator
HStack {
    Image(systemName: appState.currentMode.iconName)
        .font(.caption)
    Text(appState.currentMode.displayName)
        .font(.caption)
}
.foregroundStyle(.secondary)
```

**Step 4: Delete TranscriptionMode.swift**
```bash
rm App/BetterFasterWhisper/Sources/Core/Models/TranscriptionMode.swift
```
Also remove it from the Xcode project file — open Xcode, select the file in navigator, press Delete > Move to Trash. OR manually edit `BetterFasterWhisper.xcodeproj/project.pbxproj` to remove all references to `TranscriptionMode.swift`.

**Step 5: Build to verify**
```bash
xcodebuild -project BetterFasterWhisper.xcodeproj -scheme BetterFasterWhisper -configuration Debug build 2>&1 | grep -E "error:|BUILD"
```
Expected: `** BUILD SUCCEEDED **` with no errors.

**Step 6: Commit**
```bash
git add -A
git commit -m "feat: remove TranscriptionMode preset system"
```

---

### Task 2: Remove Modes tab from SettingsView

**Files:**
- Modify: `App/BetterFasterWhisper/Sources/UI/Screens/SettingsView.swift`

**Step 1: Remove the `modes` case from the Tab enum**

In `SettingsView.swift`, in the `Tab` enum, delete:
```swift
case modes = "Modes"
```
And its icon case:
```swift
case .modes: return "slider.horizontal.3"
```

**Step 2: Remove the Modes tab from TabView**

Delete this block from the `body` TabView:
```swift
ModesSettingsView()
    .tabItem {
        Label(Tab.modes.rawValue, systemImage: Tab.modes.icon)
    }
```

**Step 3: Delete ModesSettingsView struct**

Find `// MARK: - Modes Settings` and delete the entire `ModesSettingsView` struct (~40 lines, from `struct ModesSettingsView` to its closing `}`).

**Step 4: Build to verify**
```bash
xcodebuild -project BetterFasterWhisper.xcodeproj -scheme BetterFasterWhisper -configuration Debug build 2>&1 | grep -E "error:|BUILD"
```
Expected: `** BUILD SUCCEEDED **`

**Step 5: Commit**
```bash
git add App/BetterFasterWhisper/Sources/UI/Screens/SettingsView.swift
git commit -m "feat: remove Modes tab from Settings"
```

---

### Task 3: Rewrite MenuBarView

**Files:**
- Modify: `App/BetterFasterWhisper/Sources/UI/Screens/MenuBarView.swift`

Replace the entire file content with:

```swift
//
//  MenuBarView.swift
//  BetterFasterWhisper
//

import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var whisperService = WhisperService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Status row
            HStack(spacing: 10) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(statusText)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // Hotkey row
            HStack(spacing: 6) {
                Image(systemName: "keyboard")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(hotkeyLabel)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            Divider()

            // Settings
            Button {
                AppDelegate.shared?.openSettings()
            } label: {
                Text("Settings")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Color.primary.opacity(0.001)) // ensures hit area

            Divider()

            // Quit
            Button {
                NSApp.terminate(nil)
            } label: {
                Text("Quit")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(width: 220)
    }

    private var statusColor: Color {
        if appState.isRecording { return .red }
        if !whisperService.isInitialized { return .orange }
        return .green
    }

    private var statusText: String {
        if appState.isRecording { return "Recording..." }
        if appState.isTranscribing { return "Transcribing..." }
        if !whisperService.isInitialized { return "Loading model..." }
        return "Ready"
    }

    private var hotkeyLabel: String {
        let raw = UserDefaults.standard.string(forKey: "triggerKey") ?? "rightOption"
        switch raw {
        case "leftOption":   return "Left ⌥ Option"
        case "rightOption":  return "Right ⌥ Option"
        case "leftControl":  return "Left ⌃ Control"
        case "rightControl": return "Right ⌃ Control"
        case "leftCommand":  return "Left ⌘ Command"
        case "rightCommand": return "Right ⌘ Command"
        case "fn":           return "Fn"
        default:             return raw
        }
    }
}

/// Settings button — kept for backward compatibility if used elsewhere
struct SettingsButtonView: View {
    var body: some View {
        Button("Settings") {
            AppDelegate.shared?.openSettings()
        }
    }
}

#Preview {
    MenuBarView()
        .environmentObject(AppState.shared)
}
```

**Step 1: Replace MenuBarView.swift** with the code above.

**Step 2: Build to verify**
```bash
xcodebuild -project BetterFasterWhisper.xcodeproj -scheme BetterFasterWhisper -configuration Debug build 2>&1 | grep -E "error:|BUILD"
```
Expected: `** BUILD SUCCEEDED **`

**Step 3: Commit**
```bash
git add App/BetterFasterWhisper/Sources/UI/Screens/MenuBarView.swift
git commit -m "feat: redesign menu bar popup (status + hotkey + Settings + Quit)"
```

---

### Task 4: Redesign mini capsule

**Files:**
- Modify: `App/BetterFasterWhisper/Sources/App/AppDelegate.swift`

**Goal:** Show `mic.fill` icon at rest, FFT bars when recording, pulsing dots when transcribing.

**Step 1: Add `isActivelyRecording` to AudioLevelManager**

Find the `AudioLevelManager` class in `AppDelegate.swift`. Add this property after the existing `@Published` properties:
```swift
@Published var isActivelyRecording: Bool = false
```

**Step 2: Toggle `isActivelyRecording` in AppDelegate**

In `handleKeyDown()`, after `AppState.shared.startRecording()`, add:
```swift
AudioLevelManager.shared.isActivelyRecording = true
```

In `handleKeyUp()`, at the top of the `if AppState.shared.isRecording` branch, add:
```swift
AudioLevelManager.shared.isActivelyRecording = false
```

In `handleClassicToggle()`, in the stop path (after `AudioLevelManager.shared.isClassicRecording = false`), add:
```swift
AudioLevelManager.shared.isActivelyRecording = false
```
In the start path (after `AppState.shared.startRecording()`), add:
```swift
AudioLevelManager.shared.isActivelyRecording = true
```

In `handleClassicEscape()`, add:
```swift
AudioLevelManager.shared.isActivelyRecording = false
```

**Step 3: Replace `miniBody` in `AudioWaveformOverlay`**

Find the `miniBody` computed property and replace its content:

```swift
private var miniBody: some View {
    ZStack {
        Capsule()
            .fill(Color.black.opacity(0.85))
            .frame(width: 72, height: 28)

        if levelManager.isModelLoading {
            PulsingDotsView()
        } else if levelManager.isTranscribing {
            PulsingDotsView()
        } else if levelManager.isActivelyRecording {
            let interpolated = interpolateBands(levelManager.audioLevels, to: 12)
            let mirrored: [Float] = Array(interpolated.reversed()) + Array(interpolated)
            HStack(spacing: 1) {
                ForEach(Array(mirrored.enumerated()), id: \.offset) { _, level in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.white)
                        .frame(width: 2, height: barHeight(for: level))
                }
            }
            .animation(.spring(duration: 0.15), value: levelManager.audioLevels)
        } else {
            Image(systemName: "mic.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
        }
    }
    .frame(width: 72, height: 28)
    .animation(.easeInOut(duration: 0.2), value: levelManager.isTranscribing)
    .animation(.easeInOut(duration: 0.2), value: levelManager.isActivelyRecording)
}
```

**Step 4: Build to verify**
```bash
xcodebuild -project BetterFasterWhisper.xcodeproj -scheme BetterFasterWhisper -configuration Debug build 2>&1 | grep -E "error:|BUILD"
```
Expected: `** BUILD SUCCEEDED **`

**Step 5: Deploy and test**
```bash
pkill -9 -f BetterFasterWhisper; sleep 1
cp -R ~/Library/Developer/Xcode/DerivedData/BetterFasterWhisper-*/Build/Products/Debug/BetterFasterWhisper.app /Applications/
open /Applications/BetterFasterWhisper.app
```

Verify:
- Mini capsule shows mic icon at rest
- Bars appear when holding hotkey
- Pulsing dots appear during transcription
- Menu bar popup shows status dot + hotkey + Settings + Quit only

**Step 6: Commit**
```bash
git add App/BetterFasterWhisper/Sources/App/AppDelegate.swift
git commit -m "feat: mini capsule shows mic icon at rest, bars when recording"
```
