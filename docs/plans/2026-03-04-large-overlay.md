# Large Overlay Mode Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Ajouter un mode "Large" pour la gélule d'overlay qui affiche une capsule plus grande avec waveform élargie, indicateur de statut coloré, label de mode et timer de durée, configurable depuis les Settings.

**Architecture:** On réutilise la `NSWindow` existante et `AudioLevelManager` ; le contenu SwiftUI bascule conditionnellement selon `@AppStorage("overlayStyle")`. La fenêtre est redimensionnée dynamiquement selon le style actif. Aucun nouveau fichier de service n'est nécessaire.

**Tech Stack:** Swift 5, SwiftUI, AppKit, `@AppStorage` / `UserDefaults`, `NSHostingView`, `NSWindow`

---

### Task 1 : Exposer `recordingDuration` et `statusColor` dans `AudioLevelManager`

**Files:**
- Modify: `App/BetterFasterWhisper/Sources/App/AppDelegate.swift` (class `AudioLevelManager`, ~ligne 281)

`AudioLevelManager` est la source partagée entre `AppDelegate` et les vues SwiftUI. On doit lui ajouter la durée d'enregistrement et une couleur de statut calculée, pour que la grande gélule puisse les afficher sans accéder directement à `AppState`.

**Step 1 : Ajouter les propriétés à `AudioLevelManager`**

Dans la classe `AudioLevelManager` (après `@Published var statusMessage`), ajouter :

```swift
@Published var recordingDuration: TimeInterval = 0
```

Puis ajouter une computed property `statusColor` :

```swift
var statusColor: Color {
    if isModelLoading { return .gray }
    if isTranscribing { return .orange }
    return .blue  // recording
}
```

(`Color` est disponible via `import SwiftUI` déjà présent dans le fichier via les vues.)

**Step 2 : Alimenter `recordingDuration` depuis `AppState`**

Dans `AppState.startRecording()`, le timer existant incrémente `recordingDuration` sur `AppState`. Il faut le relayer vers `AudioLevelManager`. Dans le bloc du timer (après `self.recordingDuration += 0.1`) ajouter :

```swift
AudioLevelManager.shared.recordingDuration = self.recordingDuration
```

Dans `AppState.stopRecording()`, au moment où `isTranscribing = false` (fin de transcription), réinitialiser :

```swift
AudioLevelManager.shared.recordingDuration = 0
```

Et dans `AppState.cancelRecording()`, de même :

```swift
AudioLevelManager.shared.recordingDuration = 0
```

**Step 3 : Vérifier que ça compile**

```bash
xcodebuild -project BetterFasterWhisper.xcodeproj \
  -scheme BetterFasterWhisper -configuration Debug build 2>&1 | tail -5
```
Attendu : `** BUILD SUCCEEDED **`

**Step 4 : Commit**

```bash
git add App/BetterFasterWhisper/Sources/App/AppDelegate.swift \
        App/BetterFasterWhisper/Sources/Core/Models/AppState.swift
git commit -m "feat: expose recordingDuration and statusColor in AudioLevelManager"
```

---

### Task 2 : Créer le contenu SwiftUI de la grande gélule

**Files:**
- Modify: `App/BetterFasterWhisper/Sources/App/AppDelegate.swift` (après `PulsingDotsView`, ~ligne 427)

On ajoute un nouveau struct `LargeOverlayContent` dans le même fichier que `AudioWaveformOverlay`.

**Step 1 : Ajouter `LargeOverlayContent`**

Après le bloc `#Preview` de `PulsingDotsView` (ou juste avant `#Preview` du bas du fichier), insérer :

```swift
// MARK: - Large Overlay Content

struct LargeOverlayContent: View {
    @ObservedObject var levelManager = AudioLevelManager.shared

    private let barCount = 20
    private let capsuleHeight: CGFloat = 52
    private let capsuleWidth: CGFloat = 500

    var body: some View {
        ZStack {
            // Background
            Capsule()
                .fill(Color.black.opacity(0.88))
                .frame(width: capsuleWidth, height: capsuleHeight)

            HStack(spacing: 0) {
                // Left: status dot + mode label
                HStack(spacing: 6) {
                    Circle()
                        .fill(levelManager.statusColor)
                        .frame(width: 8, height: 8)
                        .opacity(levelManager.isModelLoading ? pulseOpacity : 1.0)

                    if levelManager.isModelLoading {
                        Text("Loading...")
                            .foregroundColor(.white.opacity(0.6))
                            .font(.system(size: 12, weight: .medium))
                    } else {
                        Text("Voice")
                            .foregroundColor(.white.opacity(0.7))
                            .font(.system(size: 12, weight: .medium))
                    }
                }
                .frame(width: 80, alignment: .leading)
                .padding(.leading, 16)

                Spacer()

                // Center: waveform or pulsing dots
                if levelManager.isModelLoading {
                    EmptyView()
                } else if levelManager.isTranscribing {
                    PulsingDotsView()
                } else {
                    HStack(spacing: 2) {
                        ForEach(0..<barCount, id: \.self) { index in
                            let level = index < levelManager.audioLevels.count
                                ? levelManager.audioLevels[index % levelManager.audioLevels.count]
                                : 0.05
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(Color.white)
                                .frame(width: 2.5, height: barHeight(for: level))
                        }
                    }
                    .animation(.easeOut(duration: 0.08), value: levelManager.audioLevels)
                }

                Spacer()

                // Right: timer
                if !levelManager.isModelLoading && !levelManager.isTranscribing {
                    Text(formatDuration(levelManager.recordingDuration))
                        .foregroundColor(.white.opacity(0.5))
                        .font(.system(size: 12, weight: .light, design: .monospaced))
                        .frame(width: 40, alignment: .trailing)
                        .padding(.trailing, 16)
                } else {
                    Spacer().frame(width: 56)
                }
            }
        }
        .frame(width: capsuleWidth, height: capsuleHeight)
    }

    // Pulse animation for status dot when loading
    @State private var pulseOpacity: Double = 1.0

    private func barHeight(for level: Float) -> CGFloat {
        let minH: CGFloat = 4
        let maxH: CGFloat = 32
        let amplified = min(1.0, level * 1.8)
        return minH + CGFloat(amplified) * (maxH - minH)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
```

**Step 2 : Ajouter un preview**

```swift
#Preview("Large Overlay") {
    LargeOverlayContent()
        .padding()
        .background(Color.gray.opacity(0.3))
}
```

**Step 3 : Vérifier que ça compile**

```bash
xcodebuild -project BetterFasterWhisper.xcodeproj \
  -scheme BetterFasterWhisper -configuration Debug build 2>&1 | tail -5
```
Attendu : `** BUILD SUCCEEDED **`

**Step 4 : Commit**

```bash
git add App/BetterFasterWhisper/Sources/App/AppDelegate.swift
git commit -m "feat: add LargeOverlayContent SwiftUI view"
```

---

### Task 3 : Brancher `AudioWaveformOverlay` sur le style choisi

**Files:**
- Modify: `App/BetterFasterWhisper/Sources/App/AppDelegate.swift` (struct `AudioWaveformOverlay`, ~ligne 315)

`AudioWaveformOverlay` est la vue racine hostée dans la `NSWindow`. On lui fait lire `overlayStyle` et déléguer le rendu.

**Step 1 : Ajouter `@AppStorage` dans `AudioWaveformOverlay`**

Dans le struct `AudioWaveformOverlay`, ajouter après `@ObservedObject var levelManager`:

```swift
@AppStorage("overlayStyle") private var overlayStyle: String = "mini"
```

**Step 2 : Remplacer le `body` par un switch sur le style**

Remplacer l'intégralité de `var body: some View { ... }` par :

```swift
var body: some View {
    if overlayStyle == "large" {
        LargeOverlayContent()
    } else {
        miniBody
    }
}

// Ancien contenu de body, renommé
private var miniBody: some View {
    ZStack {
        Capsule()
            .fill(Color.black.opacity(0.9))
            .frame(width: currentWidth, height: currentHeight)

        if levelManager.isModelLoading {
            HStack(spacing: 4) {
                PulsingDotsView()
                Text("Loading...")
                    .foregroundColor(.white)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
            }
        } else if levelManager.isTranscribing {
            PulsingDotsView()
        } else {
            HStack(spacing: 2) {
                ForEach(0..<barCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.white)
                        .frame(width: 2, height: barHeight(for: levelManager.audioLevels[index]))
                }
            }
            .animation(.easeOut(duration: 0.08), value: levelManager.audioLevels)
        }
    }
    .frame(width: waveformWidth, height: waveformHeight)
    .animation(.easeInOut(duration: 0.2), value: levelManager.isTranscribing)
}
```

**Step 3 : Vérifier que ça compile**

```bash
xcodebuild -project BetterFasterWhisper.xcodeproj \
  -scheme BetterFasterWhisper -configuration Debug build 2>&1 | tail -5
```
Attendu : `** BUILD SUCCEEDED **`

**Step 4 : Commit**

```bash
git add App/BetterFasterWhisper/Sources/App/AppDelegate.swift
git commit -m "feat: AudioWaveformOverlay delegates to mini/large based on overlayStyle"
```

---

### Task 4 : Adapter la `NSWindow` à la taille du style

**Files:**
- Modify: `App/BetterFasterWhisper/Sources/App/AppDelegate.swift` (méthodes `createMiniOverlay` et `positionMiniOverlay`)

La fenêtre NSWindow a actuellement une taille fixe 72×28. Il faut la rendre dynamique.

**Step 1 : Extraire les dimensions dans une helper**

Dans la classe `AppDelegate`, ajouter une propriété calculée :

```swift
private var overlaySize: NSSize {
    let style = UserDefaults.standard.string(forKey: "overlayStyle") ?? "mini"
    return style == "large"
        ? NSSize(width: 500, height: 52)
        : NSSize(width: 72, height: 28)
}
```

**Step 2 : Utiliser `overlaySize` dans `createMiniOverlay`**

Remplacer les deux lignes hardcodées :
```swift
let windowWidth: CGFloat = 72
let windowHeight: CGFloat = 28
```
par :
```swift
let windowWidth = overlaySize.width
let windowHeight = overlaySize.height
```

Faire de même dans `positionMiniOverlay` (mêmes constantes hardcodées un peu plus bas).

**Step 3 : Re-créer la fenêtre quand le style change**

Dans `showMiniOverlay()`, forcer la re-création si la taille a changé :

```swift
func showMiniOverlay() {
    // Re-create window if size changed (style switch)
    if let existing = miniOverlayWindow,
       existing.frame.size != overlaySize {
        existing.orderOut(nil)
        miniOverlayWindow = nil
    }

    if miniOverlayWindow == nil {
        createMiniOverlay()
    }

    AudioLevelManager.shared.reset()
    positionMiniOverlay()
    miniOverlayWindow?.orderFront(nil)
}
```

**Step 4 : Vérifier que ça compile**

```bash
xcodebuild -project BetterFasterWhisper.xcodeproj \
  -scheme BetterFasterWhisper -configuration Debug build 2>&1 | tail -5
```
Attendu : `** BUILD SUCCEEDED **`

**Step 5 : Test manuel**

```bash
# Build + déployer
xcodebuild -project BetterFasterWhisper.xcodeproj -scheme BetterFasterWhisper -configuration Debug build
pkill -9 -f BetterFasterWhisper
cp -R ~/Library/Developer/Xcode/DerivedData/BetterFasterWhisper-*/Build/Products/Debug/BetterFasterWhisper.app /Applications/
open /Applications/BetterFasterWhisper.app
```

Puis dans Terminal :
```bash
defaults write com.betterfasterwhisper.app overlayStyle large
# Relancer l'app et vérifier que la grande gélule apparaît sous le notch
defaults write com.betterfasterwhisper.app overlayStyle mini
# Relancer et vérifier que la mini réapparaît
```

**Step 6 : Commit**

```bash
git add App/BetterFasterWhisper/Sources/App/AppDelegate.swift
git commit -m "feat: dynamic NSWindow sizing based on overlayStyle"
```

---

### Task 5 : Ajouter le réglage dans `SettingsView`

**Files:**
- Modify: `App/BetterFasterWhisper/Sources/UI/Screens/SettingsView.swift` (struct `GeneralSettingsView`, ~ligne 66)

**Step 1 : Ajouter `@AppStorage("overlayStyle")` dans `GeneralSettingsView`**

Après la ligne `@AppStorage("playSound") private var playSound = true`, ajouter :

```swift
@AppStorage("overlayStyle") private var overlayStyle: String = "mini"
```

**Step 2 : Ajouter la section Overlay dans le `Form`**

Après la section `"Application"` (après le toggle `showInDock`), insérer :

```swift
Section("Overlay") {
    Picker("Style", selection: $overlayStyle) {
        Text("Mini (près du notch)").tag("mini")
        Text("Large (avec waveform élargie)").tag("large")
    }
    .pickerStyle(.menu)
    Text("La grande gélule affiche la forme d'onde, le statut et la durée d'enregistrement.")
        .font(.caption)
        .foregroundStyle(.secondary)
}
```

**Step 3 : Vérifier que ça compile**

```bash
xcodebuild -project BetterFasterWhisper.xcodeproj \
  -scheme BetterFasterWhisper -configuration Debug build 2>&1 | tail -5
```
Attendu : `** BUILD SUCCEEDED **`

**Step 4 : Test manuel end-to-end**

```bash
xcodebuild -project BetterFasterWhisper.xcodeproj -scheme BetterFasterWhisper -configuration Debug build
pkill -9 -f BetterFasterWhisper
cp -R ~/Library/Developer/Xcode/DerivedData/BetterFasterWhisper-*/Build/Products/Debug/BetterFasterWhisper.app /Applications/
open /Applications/BetterFasterWhisper.app
```

Checklist de vérification :
- [ ] Settings > General > Overlay > choisir "Large" → sauvegarder
- [ ] Relancer l'app
- [ ] Appuyer sur Right Option → la grande gélule apparaît sous le notch (500×52px)
- [ ] Point bleu visible à gauche, "Voice" label
- [ ] Forme d'onde animée au centre (20 barres)
- [ ] Timer s'incrémente : `0:01`, `0:02`...
- [ ] Relâcher → dots oranges pulsants pendant la transcription, puis gélule se cache
- [ ] Texte collé dans l'app cible
- [ ] Repasser en mode "Mini" dans Settings → mini gélule réapparaît

**Step 5 : Commit final**

```bash
git add App/BetterFasterWhisper/Sources/UI/Screens/SettingsView.swift
git commit -m "feat: add overlay style picker in General Settings"
```
