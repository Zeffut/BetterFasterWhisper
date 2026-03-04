# FFT Waveform Visualization — Design Document

## Problem

The current waveform shows a visible repetitive pattern: `audioLevels` holds only 12 RMS values, which are mapped across 40 bars using `index % 12`. The same pattern repeats 3× on screen.

## Solution

Replace the RMS time-history approach with a **real-time FFT spectral analysis** using Apple's `vDSP` (Accelerate framework). Display the 20 frequency bands as a **symmetric mirrored visualization**: low frequencies in the center, high frequencies at the edges — creating a natural arch shape when speaking.

## Architecture

### Audio pipeline change (AudioRecorder)
- Maintain a rolling buffer of the last 1024 samples (64ms at 16kHz)
- On each buffer arrival, compute FFT over the rolling window using `vDSP_fft_zrip`
- Apply a Hann window before FFT for spectral leakage reduction
- Group the 512 FFT bins into **20 log-spaced frequency bands** (80Hz–8000Hz — voice range)
- Output the 20 band amplitudes via the existing `audioLevelCallback`

### Display change (AppDelegate — SwiftUI views)
- **Large overlay (40 bars)**: mirror the 20 bands — `[bands[19...0]] + [bands[0...19]]`
- **Mini overlay (12 bars)**: use first 6 bands mirrored — `[bands[5...0]] + [bands[0...5]]`
- Animation: `.spring(duration: 0.15)` for organic movement

### Interface unchanged
- `AudioLevelManager.audioLevels: [Float]` stays the same (just receives 20 values instead of 12)
- `audioLevelCallback: ([Float]) -> Void` unchanged
- No changes to `AppState`, `HotkeyManager`, or Settings

## Frequency Bands

20 log-spaced bands from 80Hz to 8000Hz:
```
f[i] = 80 * (8000/80)^(i/20)  for i = 0..20
```
At 16kHz with 1024-point FFT: each bin = 15.625 Hz.

| Band | Freq range | Content |
|------|-----------|---------|
| 0–4  | 80–250Hz  | Fundamentals (bass) |
| 5–9  | 250–800Hz | Low-mid (vowel formants) |
| 10–14| 800–2.5kHz| Mid (consonants) |
| 15–19| 2.5–8kHz  | High-mid & presence |

## Normalization

Power from FFT → amplitude via `sqrtf` → convert to dB → map [-80dB, 0dB] to [0, 1]:
```swift
let db = 10 * log10f(power + 1e-10)
let normalized = max(0, min(1, (db + 80) / 80))
```
This gives perceptually natural scaling (quiet = short bars, loud = tall bars).
