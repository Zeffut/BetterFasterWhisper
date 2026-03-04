# SuperWhisper Redesign + Classic Recording Shortcut Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Redesigner la grande gélule pour ressembler à SuperWhisper (waveform pleine hauteur + boutons Stop/Cancel) et ajouter un raccourci clavier librement configurable pour l'enregistrement classique (toggle start/stop).

**Architecture:** `LargeOverlayContent` est entièrement redesigné en `RoundedRectangle` 520×120px avec une zone waveform haute et une barre de contrôle inférieure. `HotkeyManager` est étendu pour intercepter aussi les `keyDown` (en plus des `flagsChanged`) afin de détecter le raccourci classique configurable. `AudioLevelManager` gagne un flag `isClassicRecording` pour que l'overlay sache quand afficher Stop/Cancel. Un `ShortcutCaptureField` (NSViewRepresentable) est ajouté dans Settings > Shortcuts.

**Tech Stack:** Swift 5, SwiftUI, AppKit, NSViewRepresentable, CGEvent tap (keyDown + flagsChanged), UserDefaults/Codable

---

### Task 1 : Ajouter `isClassicRecording` à `AudioLevelManager` et mettre à jour `overlaySize`

**Files:**
- Modify: `App/BetterFasterWhisper/Sources/App/AppDelegate.swift`

**Step 1 : Ajouter `isClassicRecording` dans `AudioLevelManager`**

Dans la classe `AudioLevelManager` (après `@Published var recordingDuration`), ajouter :

```swift
@Published var isClassicRecording: Bool = false
```

**Step 2 : Mettre à jour `overlaySize` dans `AppDelegate`**

Remplacer :
```swift
? NSSize(width: 500, height: 64)
```
par :
```swift
? NSSize(width: 520, height: 120)
```

**Step 3 : Build**

```bash
xcodebuild -project BetterFasterWhisper.xcodeproj \
  -scheme BetterFasterWhisper -configuration Debug build 2>&1 | tail -3
```
Attendu : `** BUILD SUCCEEDED **`

**Step 4 : Commit**

```bash
git add App/BetterFasterWhisper/Sources/App/AppDelegate.swift
git commit -m "feat: add isClassicRecording to AudioLevelManager, resize large overlay to 520x120"
```

---

### Task 2 : Redesigner `LargeOverlayContent`

**Files:**
- Modify: `App/BetterFasterWhisper/Sources/App/AppDelegate.swift` (struct `LargeOverlayContent` + `#Preview`, ~ligne 461)

**Step 1 : Remplacer entièrement `LargeOverlayContent` et son preview**

Remplacer tout depuis `// MARK: - Large Overlay Content` jusqu'au `#Preview("Large Overlay")` inclus par :

```swift
// MARK: - Large Overlay Content

struct LargeOverlayContent: View {
    @ObservedObject var levelManager = AudioLevelManager.shared

    private let barCount = 40
    private let panelWidth: CGFloat = 520
    private let panelHeight: CGFloat = 120
    private let waveformHeight: CGFloat = 76
    private let controlBarHeight: CGFloat = 44

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.88))
                .frame(width: panelWidth, height: panelHeight)

            VStack(spacing: 0) {
                waveformArea
                    .frame(width: panelWidth, height: waveformHeight)
                    .clipped()

                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1)

                controlBar
                    .frame(width: panelWidth, height: controlBarHeight)
            }
        }
        .frame(width: panelWidth, height: panelHeight)
    }

    // MARK: Waveform

    @ViewBuilder
    private var waveformArea: some View {
        if levelManager.isModelLoading {
            Text("Loading model...")
                .foregroundColor(.white.opacity(0.45))
                .font(.system(size: 13, weight: .medium))
        } else if levelManager.isTranscribing {
            PulsingDotsView()
        } else {
            HStack(spacing: 2) {
                ForEach(0..<barCount, id: \.self) { index in
                    let level = levelManager.audioLevels[index % levelManager.audioLevels.count]
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white)
                        .frame(width: 3, height: barHeight(for: level))
                }
            }
            .animation(.easeOut(duration: 0.06), value: levelManager.audioLevels)
        }
    }

    // MARK: Control Bar

    private var controlBar: some View {
        HStack(spacing: 0) {
            // Left: status dot + state label
            HStack(spacing: 6) {
                Circle()
                    .fill(levelManager.statusColor)
                    .frame(width: 8, height: 8)
                Text(stateLabel)
                    .foregroundColor(.white.opacity(0.7))
                    .font(.system(size: 12, weight: .medium))
            }
            .frame(width: 110, alignment: .leading)
            .padding(.leading, 16)

            Spacer()

            // Center: timer (hidden during transcription/loading)
            if !levelManager.isModelLoading && !levelManager.isTranscribing {
                Text(formatDuration(levelManager.recordingDuration))
                    .foregroundColor(.white.opacity(0.45))
                    .font(.system(size: 12, weight: .light, design: .monospaced))
            }

            Spacer()

            // Right: Stop + Cancel (classic recording only)
            if levelManager.isClassicRecording {
                HStack(spacing: 8) {
                    Button("Stop") {
                        AudioLevelManager.shared.isClassicRecording = false
                        AppState.shared.stopRecording()
                    }
                    .buttonStyle(OverlayButtonStyle(isDestructive: false))

                    Button("Cancel") {
                        AudioLevelManager.shared.isClassicRecording = false
                        AppState.shared.cancelRecording()
                    }
                    .buttonStyle(OverlayButtonStyle(isDestructive: true))
                }
                .padding(.trailing, 16)
            } else {
                Spacer().frame(width: 16)
            }
        }
    }

    // MARK: Helpers

    private var stateLabel: String {
        if levelManager.isModelLoading { return "Loading..." }
        if levelManager.isTranscribing { return "Processing..." }
        return "Voice"
    }

    private func barHeight(for level: Float) -> CGFloat {
        let minH: CGFloat = 3
        let maxH: CGFloat = 64
        let amplified = min(1.0, level * 3.5)
        return minH + CGFloat(amplified) * (maxH - minH)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Overlay Button Style

struct OverlayButtonStyle: ButtonStyle {
    let isDestructive: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(isDestructive ? Color.red.opacity(0.9) : Color.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.white.opacity(configuration.isPressed ? 0.25 : 0.12))
            .clipShape(Capsule())
    }
}

#Preview("Large Overlay") {
    LargeOverlayContent()
        .padding()
        .background(Color.gray.opacity(0.3))
}
```

**Step 2 : Build**

```bash
xcodebuild -project BetterFasterWhisper.xcodeproj \
  -scheme BetterFasterWhisper -configuration Debug build 2>&1 | tail -3
```
Attendu : `** BUILD SUCCEEDED **`

**Step 3 : Commit**

```bash
git add App/BetterFasterWhisper/Sources/App/AppDelegate.swift
git commit -m "feat: redesign LargeOverlayContent to match SuperWhisper (waveform + Stop/Cancel bar)"
```

---

### Task 3 : `ClassicShortcut` model + extension `HotkeyManager`

**Files:**
- Modify: `App/BetterFasterWhisper/Sources/Core/Services/HotkeyManager.swift`
- Modify: `App/BetterFasterWhisper/Sources/App/AppDelegate.swift`

**Step 1 : Ajouter `ClassicShortcut` au début de `HotkeyManager.swift` (après les imports)**

Après la ligne `private let logger = ...`, insérer :

```swift
// MARK: - Classic Shortcut Model

struct ClassicShortcut: Codable, Equatable {
    let keyCode: UInt16
    let modifierFlags: UInt64

    /// Modifier mask : only Ctrl/Opt/Shift/Cmd bits
    static let modifierMask: UInt64 =
        CGEventFlags.maskControl.rawValue |
        CGEventFlags.maskAlternate.rawValue |
        CGEventFlags.maskShift.rawValue |
        CGEventFlags.maskCommand.rawValue

    /// Key codes that are modifier keys only (should not be used as the main key)
    static let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]

    var displayString: String {
        var s = ""
        let flags = CGEventFlags(rawValue: modifierFlags)
        if flags.contains(.maskControl) { s += "⌃" }
        if flags.contains(.maskAlternate) { s += "⌥" }
        if flags.contains(.maskShift) { s += "⇧" }
        if flags.contains(.maskCommand) { s += "⌘" }
        s += Self.keyCodeToString(keyCode)
        return s
    }

    func matches(event: CGEvent) -> Bool {
        let eventKeyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let eventFlags = event.flags.rawValue & Self.modifierMask
        return eventKeyCode == keyCode && eventFlags == modifierFlags
    }

    /// Build a ClassicShortcut from a CGEvent keyDown. Returns nil if invalid.
    static func from(event: CGEvent) -> ClassicShortcut? {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        guard !modifierKeyCodes.contains(keyCode) else { return nil }
        let flags = event.flags.rawValue & modifierMask
        guard flags != 0 else { return nil }
        return ClassicShortcut(keyCode: keyCode, modifierFlags: flags)
    }

    static func keyCodeToString(_ keyCode: UInt16) -> String {
        let map: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L",
            38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
            45: "N", 46: "M", 47: ".", 48: "Tab", 49: "Space", 50: "`",
            51: "⌫", 53: "Esc", 96: "F5", 97: "F6", 98: "F7", 99: "F3",
            100: "F8", 101: "F9", 103: "F11", 109: "F10", 111: "F12",
            118: "F4", 120: "F2", 122: "F1", 123: "←", 124: "→", 125: "↓", 126: "↑"
        ]
        return map[keyCode] ?? "Key\(keyCode)"
    }
}
```

**Step 2 : Ajouter les propriétés et callbacks dans `HotkeyManager`**

Dans la classe `HotkeyManager`, après `var onKeyUp: (() -> Void)?`, ajouter :

```swift
/// Current classic recording shortcut.
@Published var classicShortcut: ClassicShortcut? {
    didSet { saveClassicShortcut() }
}

/// Called when the classic shortcut is pressed (toggle start/stop).
var onClassicToggle: (() -> Void)?

/// Called when Escape is pressed (cancel classic recording).
var onClassicEscape: (() -> Void)?
```

**Step 3 : Charger `classicShortcut` dans `init()`**

Dans `private init()`, après le bloc de chargement de `triggerKey`, ajouter :

```swift
// Load classic recording shortcut
if let data = UserDefaults.standard.data(forKey: "classicRecordingShortcut"),
   let shortcut = try? JSONDecoder().decode(ClassicShortcut.self, from: data) {
    self.classicShortcut = shortcut
} else {
    self.classicShortcut = nil
}
```

**Step 4 : Ajouter `saveClassicShortcut()` après `saveTriggerKey()`**

```swift
private func saveClassicShortcut() {
    if let shortcut = classicShortcut,
       let data = try? JSONEncoder().encode(shortcut) {
        UserDefaults.standard.set(data, forKey: "classicRecordingShortcut")
    } else {
        UserDefaults.standard.removeObject(forKey: "classicRecordingShortcut")
    }
}
```

**Step 5 : Étendre le `eventMask` dans `startListening()` pour inclure `keyDown`**

Remplacer :
```swift
let eventMask = (1 << CGEventType.flagsChanged.rawValue)
```
par :
```swift
let eventMask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
```

**Step 6 : Refactoriser `handleCGEvent` pour router flagsChanged vs keyDown**

Remplacer la méthode `handleCGEvent` entière par :

```swift
private func handleCGEvent(_ event: CGEvent) {
    switch event.type {
    case .flagsChanged:
        handleFlagsChanged(event)
    case .keyDown:
        handleKeyDown(event)
    default:
        break
    }
}

private func handleFlagsChanged(_ event: CGEvent) {
    let currentFlags = event.flags.rawValue
    let flagMask = triggerKey.deviceFlagMask

    logger.warning("CGEvent flags=\(currentFlags, format: .hex), mask=\(flagMask, format: .hex)")

    let wasPressed = (previousFlags & flagMask) != 0
    let isPressed = (currentFlags & flagMask) != 0
    previousFlags = currentFlags

    if isPressed && !wasPressed {
        logger.warning(">>> KEY DOWN (\(self.triggerKey.displayName))")
        print("[HotkeyManager] >>> KEY DOWN")
        isKeyDown = true
        DispatchQueue.main.async { [weak self] in
            self?.onKeyDown?()
        }
    } else if !isPressed && wasPressed {
        logger.warning(">>> KEY UP (\(self.triggerKey.displayName))")
        print("[HotkeyManager] >>> KEY UP")
        isKeyDown = false
        DispatchQueue.main.async { [weak self] in
            self?.onKeyUp?()
        }
    }
}

private func handleKeyDown(_ event: CGEvent) {
    let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

    // Escape → cancel classic recording
    if keyCode == 53 {
        DispatchQueue.main.async { [weak self] in
            self?.onClassicEscape?()
        }
        return
    }

    // Classic shortcut match
    if let shortcut = classicShortcut, shortcut.matches(event: event) {
        DispatchQueue.main.async { [weak self] in
            self?.onClassicToggle?()
        }
    }
}
```

**Step 7 : Câbler les callbacks dans `AppDelegate.setupPushToTalk()`**

Dans `AppDelegate`, la méthode `setupPushToTalk()` configure déjà `onKeyDown` et `onKeyUp`. Après la ligne `hotkeyManager.onKeyUp = { ... }`, ajouter :

```swift
hotkeyManager.onClassicToggle = {
    Task { @MainActor in
        self.handleClassicToggle()
    }
}

hotkeyManager.onClassicEscape = {
    Task { @MainActor in
        self.handleClassicEscape()
    }
}
```

**Step 8 : Ajouter `handleClassicToggle()` et `handleClassicEscape()` dans `AppDelegate`**

Après `handleKeyUp()`, ajouter :

```swift
@MainActor
private func handleClassicToggle() {
    guard !AppState.shared.isTranscribing else { return }

    if AppState.shared.isRecording {
        // Stop and transcribe
        AudioLevelManager.shared.isClassicRecording = false
        AppState.shared.stopRecording()
        MediaControlManager.shared.resumeMedia()
        scheduleHideOverlay(delay: 10.0)
    } else {
        // Start recording
        showMiniOverlay()
        guard AppState.shared.isEngineReady else {
            AudioLevelManager.shared.setLoading(true, message: "Loading model...")
            return
        }
        AudioLevelManager.shared.setLoading(false)
        AudioLevelManager.shared.isClassicRecording = true
        MediaControlManager.shared.pauseMedia()
        AppState.shared.startRecording()
    }
}

@MainActor
private func handleClassicEscape() {
    guard AudioLevelManager.shared.isClassicRecording else { return }
    AudioLevelManager.shared.isClassicRecording = false
    AppState.shared.cancelRecording()
}
```

**Step 9 : Build**

```bash
xcodebuild -project BetterFasterWhisper.xcodeproj \
  -scheme BetterFasterWhisper -configuration Debug build 2>&1 | tail -3
```
Attendu : `** BUILD SUCCEEDED **`

**Step 10 : Commit**

```bash
git add App/BetterFasterWhisper/Sources/Core/Services/HotkeyManager.swift \
        App/BetterFasterWhisper/Sources/App/AppDelegate.swift
git commit -m "feat: add ClassicShortcut model and classic recording toggle in HotkeyManager"
```

---

### Task 4 : `ShortcutCaptureField` + section Classic Recording dans Settings

**Files:**
- Modify: `App/BetterFasterWhisper/Sources/UI/Screens/SettingsView.swift`

**Step 1 : Ajouter `ShortcutCaptureField` (NSViewRepresentable) à la fin du fichier**

Avant le `#Preview` final du fichier, insérer :

```swift
// MARK: - Shortcut Capture Field

struct ShortcutCaptureField: NSViewRepresentable {
    @Binding var shortcut: ClassicShortcut?

    func makeNSView(context: Context) -> ShortcutCaptureNSView {
        let view = ShortcutCaptureNSView()
        view.onShortcutChanged = { newShortcut in
            shortcut = newShortcut
        }
        return view
    }

    func updateNSView(_ nsView: ShortcutCaptureNSView, context: Context) {
        nsView.currentShortcut = shortcut
    }
}

class ShortcutCaptureNSView: NSView {
    var currentShortcut: ClassicShortcut? { didSet { updateDisplay() } }
    var onShortcutChanged: ((ClassicShortcut?) -> Void)?

    private var isCapturing = false
    private let label = NSTextField(labelWithString: "")
    private let clearButton = NSButton(title: "×", target: nil, action: nil)

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1

        label.isEditable = false
        label.isBordered = false
        label.backgroundColor = .clear
        label.alignment = .center
        label.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        addSubview(label)

        clearButton.bezelStyle = .rounded
        clearButton.isBordered = false
        clearButton.font = .systemFont(ofSize: 14)
        clearButton.target = self
        clearButton.action = #selector(clearShortcut)
        addSubview(clearButton)

        let click = NSClickGestureRecognizer(target: self, action: #selector(startCapture))
        addGestureRecognizer(click)

        updateDisplay()
    }

    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height
        let btnW: CGFloat = clearButton.isHidden ? 0 : h
        clearButton.frame = NSRect(x: w - btnW, y: 0, width: btnW, height: h)
        label.frame = NSRect(x: 8, y: 0, width: w - btnW - 8, height: h)
    }

    private func updateDisplay() {
        if isCapturing {
            label.stringValue = "Press keys..."
            label.textColor = .white
            layer?.backgroundColor = NSColor.systemBlue.cgColor
            layer?.borderColor = NSColor.clear.cgColor
            clearButton.isHidden = true
        } else if let s = currentShortcut {
            label.stringValue = s.displayString
            label.textColor = .labelColor
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            layer?.borderColor = NSColor.separatorColor.cgColor
            clearButton.isHidden = false
        } else {
            label.stringValue = "Click to record shortcut"
            label.textColor = .placeholderTextColor
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            layer?.borderColor = NSColor.separatorColor.cgColor
            clearButton.isHidden = true
        }
        needsLayout = true
    }

    @objc private func startCapture() {
        guard !isCapturing else { return }
        isCapturing = true
        window?.makeFirstResponder(self)
        updateDisplay()
    }

    @objc private func clearShortcut() {
        onShortcutChanged?(nil)
        isCapturing = false
        updateDisplay()
    }

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard isCapturing else { return }

        // Escape cancels capture without changing shortcut
        if event.keyCode == 53 {
            isCapturing = false
            updateDisplay()
            return
        }

        // Build modifier flags from NSEvent
        var flags: UInt64 = 0
        if event.modifierFlags.contains(.control) { flags |= CGEventFlags.maskControl.rawValue }
        if event.modifierFlags.contains(.option)  { flags |= CGEventFlags.maskAlternate.rawValue }
        if event.modifierFlags.contains(.shift)   { flags |= CGEventFlags.maskShift.rawValue }
        if event.modifierFlags.contains(.command) { flags |= CGEventFlags.maskCommand.rawValue }

        guard flags != 0 else { return } // Need at least one modifier

        let captured = ClassicShortcut(keyCode: event.keyCode, modifierFlags: flags)
        isCapturing = false
        onShortcutChanged?(captured)
        updateDisplay()
    }
}
```

**Step 2 : Ajouter la section Classic Recording dans `ShortcutsSettingsView`**

Dans `ShortcutsSettingsView`, ajouter une propriété pour le raccourci en tête du struct :

```swift
@ObservedObject private var hotkeyManager = HotkeyManager.shared
```

(déjà présent)

Puis après la `Section("Push-to-Talk") { ... }`, insérer :

```swift
Section("Classic Recording") {
    VStack(alignment: .leading, spacing: 12) {
        Text("Global Shortcut")
            .font(.headline)

        Text("Press once to start recording, press again (or click Stop) to transcribe. Esc cancels.")
            .font(.caption)
            .foregroundStyle(.secondary)

        ShortcutCaptureField(shortcut: Binding(
            get: { hotkeyManager.classicShortcut },
            set: { hotkeyManager.classicShortcut = $0 }
        ))
        .frame(height: 32)
    }
    .padding(.vertical, 8)
}
```

**Step 3 : Build**

```bash
xcodebuild -project BetterFasterWhisper.xcodeproj \
  -scheme BetterFasterWhisper -configuration Debug build 2>&1 | tail -3
```
Attendu : `** BUILD SUCCEEDED **`

**Step 4 : Test manuel**

```bash
xcodebuild -project BetterFasterWhisper.xcodeproj -scheme BetterFasterWhisper -configuration Debug build
pkill -9 -f BetterFasterWhisper
cp -R ~/Library/Developer/Xcode/DerivedData/BetterFasterWhisper-*/Build/Products/Debug/BetterFasterWhisper.app /Applications/
open /Applications/BetterFasterWhisper.app
```

Checklist :
- [ ] Settings > Shortcuts > Classic Recording → cliquer le champ → presser ⌘⇧R → affiche `⌘⇧R`
- [ ] Bouton `×` efface le raccourci
- [ ] Relancer l'app, raccourci toujours présent (persisté)
- [ ] Appuyer ⌘⇧R → grande gélule apparaît, barres animent, boutons Stop et Cancel visibles
- [ ] Cliquer Stop → transcrit et colle le texte, gélule se cache
- [ ] Appuyer ⌘⇧R → démarrer → appuyer Esc → annulé sans transcription
- [ ] Appuyer ⌘⇧R → démarrer → appuyer ⌘⇧R à nouveau → stop et transcrit
- [ ] Push-to-talk (Right Option) fonctionne toujours (sans boutons Stop/Cancel)

**Step 5 : Commit**

```bash
git add App/BetterFasterWhisper/Sources/UI/Screens/SettingsView.swift
git commit -m "feat: add ShortcutCaptureField and Classic Recording section in Settings"
```
