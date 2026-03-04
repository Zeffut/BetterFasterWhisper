# Design : Redesign SuperWhisper + Raccourci Enregistrement Classique

**Date :** 2026-03-04
**Inspiré de :** SuperWhisper recording window

---

## Contexte

L'overlay large actuel (500×64px capsule) ne ressemble pas assez à SuperWhisper. On veut :
1. Un redesign visuel (rectangle arrondi, waveform qui remplit la fenêtre, boutons Stop/Cancel)
2. Un raccourci clavier configurable librement pour démarrer/arrêter un enregistrement classique (toggle, pas push-to-talk)

---

## Partie 1 — Redesign visuel de la grande gélule

### Layout

```
╭─────────────────────────────────────────────────╮
│                                                 │
│  ▁▃▅▇▅▃▁▂▅▇▇▅▂▁▃▆▇▆▃▁▂▅▇▅▃▁▃▆▇▆▃▂▁▅▇▅▂▁▃▅▇     │
│                                                 │
├─────────────────────────────────────────────────┤
│ ● Voice          0:08      [  Stop  ]  [Cancel] │
╰─────────────────────────────────────────────────╯
```

### Dimensions
- **Taille :** 520×120px (vs 500×64px actuel)
- **Forme :** `RoundedRectangle(cornerRadius: 16)` (vs `Capsule()` actuel)
- **Fond :** `Color.black.opacity(0.88)`

### Zone waveform (partie supérieure, ~76px)
- Remplit toute la largeur de la fenêtre (padding horizontal 12px de chaque côté)
- 40 barres, width: 3px, spacing: 2px, cornerRadius: 2
- minH: 3px, maxH: 64px, amplification: ×3.5
- Animation: `.easeOut(duration: 0.06)`
- État transcription : `PulsingDotsView()` centré
- État chargement : `Text("Loading model...")` centré

### Barre de contrôle inférieure (~44px)
Séparée par un `Divider()` de la zone waveform.

| Zone | Contenu |
|------|---------|
| Gauche | `Circle` (statusColor, 8pt) + `Text` (label d'état) |
| Centre | `Text` (timer monospace, `0:08`) |
| Droite | `[Stop]` + `[Cancel]` (seulement si `isClassicRecording`) |

- **Stop** → `AppState.shared.stopRecording()` + ferme overlay
- **Cancel** → `AppState.shared.cancelRecording()` + ferme overlay
- Boutons stylés : `.buttonStyle(.plain)` avec fond pill gris semi-transparent

### États
| État | Waveform zone | Label | Boutons |
|------|--------------|-------|---------|
| Chargement | `"Loading model..."` | `"Loading..."` | cachés |
| Push-to-talk actif | barres animées | `"Voice"` | cachés |
| Classic actif | barres animées | `"Voice"` | Stop + Cancel |
| Transcription | PulsingDotsView | `"Processing..."` | cachés |

---

## Partie 2 — Raccourci clavier d'enregistrement classique

### Modèle de données

```swift
struct ClassicShortcut: Codable {
    let keyCode: UInt16
    let modifierFlags: UInt64   // CGEventFlags.rawValue
    var displayString: String   // ex: "⌘⇧R"
}
```

Stocké en UserDefaults sous la clé `"classicRecordingShortcut"` (JSON).

### Comportement
- 1ère pression → `startRecording()` + `AudioLevelManager.shared.isClassicRecording = true`
- 2ème pression (même raccourci) → `stopRecording()`
- `Escape` → `cancelRecording()`
- Si déjà en transcription : ignoré

### Extension HotkeyManager
- Étendre le `CGEventMask` du tap existant pour inclure `keyDown` (en plus de `flagsChanged`)
- Dans `handleCGEvent`, si l'événement est `keyDown` : vérifier keyCode + modifiers vs `classicShortcut`
- Si match et pas en recording → start ; si match et en recording → stop
- Écouter `Escape` (keyCode 53) pour cancel quand `isClassicRecording`

### AudioLevelManager
Ajouter : `@Published var isClassicRecording: Bool = false`

Réinitialiser à `false` dans `stopRecording()` et `cancelRecording()`.

---

## Partie 3 — UI de capture du raccourci dans Settings

### Onglet Shortcuts (ShortcutsSettingsView)

Nouvelle section après "Push-to-Talk" :

```
Section("Classic Recording") {
    ShortcutCaptureField(shortcut: $classicShortcut)
    Text("Press shortcut → start. Press again or Stop → transcribe. Esc → cancel.")
        .font(.caption).foregroundStyle(.secondary)
}
```

### ShortcutCaptureField

`NSViewRepresentable` wrappant un `NSTextField` custom (`ShortcutCaptureView: NSTextField`) :

- Affichage normal : badge pill avec le raccourci (ex: `⌘⇧R`) + bouton `×` pour effacer
- Clic sur le badge → entre en mode capture : affiche `"Press keys..."` (fond bleu)
- Pression d'une combo valide (au moins un modifier + une touche non-modifier) → sauvegarde et sort du mode capture
- Pression d'Escape en mode capture → annule la capture sans changer
- Liaison via `Binding<ClassicShortcut?>` (nil = désactivé)

### Validation
Une combinaison valide = au moins un modifier (Cmd, Opt, Ctrl, Shift) + une touche normale (pas juste modifier seul).

---

## Architecture — fichiers modifiés

| Fichier | Changement |
|---------|-----------|
| `AppDelegate.swift` (AudioLevelManager) | +`isClassicRecording: Bool` |
| `AppDelegate.swift` (LargeOverlayContent) | Redesign complet : RoundedRectangle, waveform haute, barre de contrôle avec Stop/Cancel |
| `AppDelegate.swift` (overlaySize) | 520×120 pour large |
| `HotkeyManager.swift` | +`classicShortcut`, étend eventMask à keyDown, gère toggle + Escape |
| `SettingsView.swift` (ShortcutsSettingsView) | +section Classic Recording + ShortcutCaptureField |
| `SettingsView.swift` (ShortcutCaptureField) | Nouveau NSViewRepresentable |

## Ce qui ne change pas

- Le mode mini reste identique
- La logique push-to-talk reste inchangée
- `AppState`, `AudioRecorder`, `WhisperService` : aucune modification
