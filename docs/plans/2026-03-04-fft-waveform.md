# FFT Waveform Visualization Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the repetitive RMS time-history waveform with a real-time FFT spectral visualization displayed as a symmetric mirrored arch (low frequencies center, high frequencies edges).

**Architecture:** `AudioRecorder` accumulates a 1024-sample rolling buffer, computes FFT via `vDSP`, groups 512 bins into 20 log-spaced bands (80Hz–8kHz), and sends the 20 amplitudes via the existing callback. The SwiftUI views mirror those 20 bands symmetrically.

**Tech Stack:** Swift 5, Accelerate (vDSP), SwiftUI, AppKit

---

### Task 1: Add FFT computation to AudioRecorder

**Files:**
- Modify: `App/BetterFasterWhisper/Sources/Core/Audio/AudioRecorder.swift`

**Step 1: Add `import Accelerate` at the top of the file**

After the existing imports, add:
```swift
import Accelerate
```

**Step 2: Add FFT properties to the `AudioRecorder` class**

After `private let waveformBarCount = 12`, replace with:
```swift
private let waveformBarCount = 20   // 20 FFT frequency bands
private let fftSize = 1024          // FFT window size (64ms at 16kHz)
private let fftBandCount = 20
private let fftMinHz: Float = 80
private let fftMaxHz: Float = 8000
private var fftSetup: FFTSetup?
private var fftWindow: [Float] = []
private var fftRollingBuffer: [Float] = []
```

**Step 3: Initialize FFT in `init()` (or wherever the class is initialized)**

Find `private init()` or `init()` in AudioRecorder. Add at the end:
```swift
// FFT setup
let log2n = vDSP_Length(log2(Float(fftSize)))
fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))
fftWindow = [Float](repeating: 0, count: fftSize)
vDSP_hann_window(&fftWindow, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
fftRollingBuffer = [Float](repeating: 0, count: fftSize)
```

**Step 4: Add the `computeFFTBands(from:)` method**

Add this private method to AudioRecorder:
```swift
private func computeFFTBands(from samples: [Float]) -> [Float] {
    guard let setup = fftSetup, samples.count == fftSize else {
        return [Float](repeating: 0, count: fftBandCount)
    }

    // Apply Hann window
    var windowed = [Float](repeating: 0, count: fftSize)
    vDSP_vmul(samples, 1, fftWindow, 1, &windowed, 1, vDSP_Length(fftSize))

    // Pack real samples into split-complex format (half size)
    var realPart = [Float](repeating: 0, count: fftSize / 2)
    var imagPart = [Float](repeating: 0, count: fftSize / 2)
    let log2n = vDSP_Length(log2(Float(fftSize)))

    realPart.withUnsafeMutableBufferPointer { rBuf in
        imagPart.withUnsafeMutableBufferPointer { iBuf in
            var split = DSPSplitComplex(realp: rBuf.baseAddress!, imagp: iBuf.baseAddress!)
            windowed.withUnsafeBytes { rawBytes in
                rawBytes.bindMemory(to: DSPComplex.self).baseAddress.map { cPtr in
                    vDSP_ctoz(cPtr, 2, &split, 1, vDSP_Length(fftSize / 2))
                    vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                    var magnitudes = [Float](repeating: 0, count: fftSize / 2)
                    vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(fftSize / 2))

                    // Group bins into log-spaced bands and normalize to [0, 1]
                    let hzPerBin = Float(targetSampleRate) / Float(fftSize)
                    var bands = [Float](repeating: 0, count: fftBandCount)
                    for i in 0..<fftBandCount {
                        let fLow  = fftMinHz * pow(fftMaxHz / fftMinHz, Float(i)     / Float(fftBandCount))
                        let fHigh = fftMinHz * pow(fftMaxHz / fftMinHz, Float(i + 1) / Float(fftBandCount))
                        let binLow  = max(1, Int(fLow  / hzPerBin))
                        let binHigh = min(fftSize / 2 - 1, Int(fHigh / hzPerBin))
                        guard binLow <= binHigh else { continue }
                        var avg: Float = 0
                        vDSP_meanv(magnitudes.advanced(by: binLow), 1, &avg, vDSP_Length(binHigh - binLow + 1))
                        // dB normalization: map [-80dB, 0dB] → [0, 1]
                        let db = 10 * log10f(avg + 1e-10)
                        bands[i] = max(0, min(1, (db + 80) / 80))
                    }
                    recentLevels = bands
                }
            }
        }
    }
    return recentLevels
}
```

**Step 5: Replace the RMS+shift logic in `processAudioBuffer` with FFT**

Find the block that currently does:
```swift
let rms = calculateRMS(samples: samplesToAdd)
let normalizedLevel = min(1.0, rms * 8)
recentLevels.removeFirst()
recentLevels.append(normalizedLevel)
let levels = recentLevels
let callback = audioLevelCallback
DispatchQueue.main.async {
    callback?(levels)
}
```

Replace it with:
```swift
// Accumulate into rolling buffer
fftRollingBuffer.append(contentsOf: samplesToAdd)
if fftRollingBuffer.count > fftSize {
    fftRollingBuffer.removeFirst(fftRollingBuffer.count - fftSize)
}

// Compute FFT bands once we have a full window
if fftRollingBuffer.count == fftSize {
    let bands = computeFFTBands(from: fftRollingBuffer)
    let callback = audioLevelCallback
    DispatchQueue.main.async {
        callback?(bands)
    }
}
```

**Step 6: Update `reset()` to use the new count**

Find `recentLevels = Array(repeating: 0, count: waveformBarCount)` in `reset()` (or wherever `recentLevels` is initialized). Make sure it uses `waveformBarCount` (now 20). It should already work since `waveformBarCount = 20`.

Also reset the rolling buffer in the recording start:
```swift
fftRollingBuffer = [Float](repeating: 0, count: fftSize)
```
Add this where `audioBuffer.removeAll()` and `recentLevels = ...` are already reset (in `startRecording()` before the tap is installed).

**Step 7: Also update `AudioLevelManager.reset()`**

In AppDelegate.swift, find:
```swift
audioLevels = Array(repeating: 0.05, count: 12)
```
Change to:
```swift
audioLevels = Array(repeating: 0, count: 20)
```

**Step 8: Build**

```bash
xcodebuild -project BetterFasterWhisper.xcodeproj \
  -scheme BetterFasterWhisper -configuration Debug build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

**Step 9: Commit**

```bash
git add App/BetterFasterWhisper/Sources/Core/Audio/AudioRecorder.swift \
        App/BetterFasterWhisper/Sources/App/AppDelegate.swift
git commit -m "feat: replace RMS waveform with FFT spectral analysis (20 log-spaced bands)"
```

---

### Task 2: Update Large Overlay — symmetric mirrored display

**Files:**
- Modify: `App/BetterFasterWhisper/Sources/App/AppDelegate.swift` (struct `LargeOverlayContent`, `waveformArea`)

**Step 1: Update `waveformArea` in `LargeOverlayContent`**

Find the `waveformArea` computed property. Replace the `HStack` that currently does `index % levelManager.audioLevels.count`:

```swift
// Old:
HStack(spacing: 2) {
    ForEach(0..<barCount, id: \.self) { index in
        let level = levelManager.audioLevels[index % levelManager.audioLevels.count]
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.white)
            .frame(width: 3, height: barHeight(for: level))
    }
}
.animation(.easeOut(duration: 0.06), value: levelManager.audioLevels)
```

Replace with:
```swift
// New: mirror 20 bands symmetrically (bands[19...0] + bands[0...19])
let bands = levelManager.audioLevels
let mirrored: [Float] = bands.reversed() + bands

HStack(spacing: 2) {
    ForEach(0..<mirrored.count, id: \.self) { index in
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.white)
            .frame(width: 3, height: barHeight(for: mirrored[index]))
    }
}
.animation(.spring(duration: 0.15), value: levelManager.audioLevels)
```

**Step 2: Remove the `barCount` constant** (it's no longer needed since mirrored drives the count)

Remove `private let barCount = 40` from `LargeOverlayContent`.

**Step 3: Build**

```bash
xcodebuild -project BetterFasterWhisper.xcodeproj \
  -scheme BetterFasterWhisper -configuration Debug build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

**Step 4: Commit**

```bash
git add App/BetterFasterWhisper/Sources/App/AppDelegate.swift
git commit -m "feat: mirror 20 FFT bands symmetrically in large overlay (40 bars)"
```

---

### Task 3: Update Mini Overlay — symmetric mirrored display

**Files:**
- Modify: `App/BetterFasterWhisper/Sources/App/AppDelegate.swift` (struct `AudioWaveformOverlay`, `miniBody`)

**Step 1: Find `miniBody` in `AudioWaveformOverlay`**

Locate the `HStack` that renders the 12 waveform bars in the mini overlay. It currently does:
```swift
ForEach(0..<barCount, id: \.self) { index in
    RoundedRectangle(cornerRadius: 1)
        .fill(Color.white)
        .frame(width: 2, height: barHeight(for: levelManager.audioLevels[index % levelManager.audioLevels.count]))
}
```

Replace with (using first 6 of the 20 bands, mirrored):
```swift
let bands = Array(levelManager.audioLevels.prefix(6))
let mirrored: [Float] = bands.reversed() + bands

ForEach(0..<mirrored.count, id: \.self) { index in
    RoundedRectangle(cornerRadius: 1)
        .fill(Color.white)
        .frame(width: 2, height: barHeight(for: mirrored[index]))
}
```

Also update the animation on that HStack from `.easeOut(duration: 0.08)` to `.spring(duration: 0.15)`.

**Step 2: Remove the `barCount` constant from `AudioWaveformOverlay`** (if present — `private let barCount = 12`)

**Step 3: Build**

```bash
xcodebuild -project BetterFasterWhisper.xcodeproj \
  -scheme BetterFasterWhisper -configuration Debug build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

**Step 4: Deploy and test manually**

```bash
pkill -9 -f BetterFasterWhisper
cp -R ~/Library/Developer/Xcode/DerivedData/BetterFasterWhisper-*/Build/Products/Debug/BetterFasterWhisper.app /Applications/
open /Applications/BetterFasterWhisper.app
```

Checklist:
- [ ] Press Right Option, speak → mini overlay shows symmetric waveform, no repetition
- [ ] Bars in center (bass) move more than edges (treble) during speech
- [ ] Both halves are visually symmetric (mirror image)
- [ ] Large overlay (if configured) shows the same symmetric pattern at 40 bars
- [ ] Silence → bars collapse to near-zero height
- [ ] Loud sound → bars grow toward center peak

**Step 5: Commit**

```bash
git add App/BetterFasterWhisper/Sources/App/AppDelegate.swift
git commit -m "feat: mirror FFT bands in mini overlay (12 bars from first 6 bands)"
```
