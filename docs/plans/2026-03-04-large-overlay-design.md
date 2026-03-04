# Design : Grande gélule d'overlay (mode Large)

**Date :** 2026-03-04
**Inspiré de :** SuperWhisper recording window

---

## Contexte

L'overlay actuel est une petite gélule 72×28px positionnée sous le notch. L'objectif est d'ajouter un mode "Large" optionnel : une capsule plus grande affichant plus d'informations, sans remplacer le mode mini.

## Design visuel

```
╭──────────────────────────────────────────────────╮
│ ● Voice   ▮▯▮▮▯▮▮▮▯▮▯▮▮▯▮▮▮▯▮▯▮▮▮   0:08        │
╰──────────────────────────────────────────────────╯
```

- **Taille :** ~500×52px (vs 72×28px pour le mini)
- **Fond :** `rgba(0,0,0,0.88)` avec flou vitreous (`NSVisualEffectView` ou fond SwiftUI)
- **Coins :** `26px` radius (capsule/pill)
- **Position :** sous le notch, centré horizontalement (même logique que mini)

### Éléments

| Élément | Position | Détail |
|---------|----------|--------|
| Point de statut | Gauche | bleu=enregistrement, orange=transcription, gris=chargement |
| Label mode | À côté du point | `"Voice"` ou langue active |
| Forme d'onde | Centre | 20 barres (vs 12 en mini), même `AudioLevelManager` |
| Timer | Droite | `"0:08"`, monospace, gris clair. Caché en état transcription/chargement |

### États

| État | Point | Waveform | Timer |
|------|-------|----------|-------|
| Chargement modèle | gris animé (pulse) | `"Loading model..."` text | caché |
| Enregistrement | bleu | barres animées | visible |
| Transcription | orange pulsant | 3 dots pulsants | caché |

> **Note importante :** Le bouton Stop n'est affiché que pour un enregistrement non push-to-talk (enregistrement classique déclenché manuellement). En push-to-talk, relâcher la touche suffit — pas de bouton.

## Architecture

### Nouveau UserDefaults

- **Clé :** `overlayStyle`
- **Valeurs :** `"mini"` (défaut) | `"large"`

### Modifications fichiers

1. **`AppDelegate.swift`**
   - `positionMiniOverlay()` → renommer en `positionOverlay()`
   - Redimensionner la `NSWindow` selon le style actif
   - La fenêtre est unique, seul le contenu SwiftUI change

2. **`AppDelegate.swift` (AudioWaveformOverlay)**
   - Lire `@AppStorage("overlayStyle")`
   - Branching conditionnel : `MiniOverlayContent` vs `LargeOverlayContent`
   - `LargeOverlayContent` : HStack avec point statut + label + waveform élargie + timer

3. **`AppDelegate.swift` (AudioLevelManager)**
   - Ajouter `recordingDuration: TimeInterval` publié (alimenté depuis `AppState.recordingDuration`)
   - Ajouter `statusColor: Color` calculé depuis l'état courant

4. **`SettingsView.swift` (GeneralSettingsView)**
   - Ajouter section "Overlay" avec `Picker("Style", selection: $overlayStyle)` → Mini / Large

## Ce qui ne change pas

- `AudioLevelManager` reste la source de vérité pour les niveaux audio
- La `NSWindow` reste unique (pas de seconde fenêtre)
- La logique de positionnement reste sous le notch
- Le mode mini reste inchangé et identique visuellement
