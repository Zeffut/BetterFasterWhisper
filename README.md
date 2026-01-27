# BetterFasterWhisper

A free, open-source voice-to-text application for macOS, powered by WhisperKit and optimized for Apple Silicon.

**BetterFasterWhisper** is a 100% local, privacy-first alternative to [SuperWhisper](https://superwhisper.com). No subscriptions, no API costs, no data ever leaves your device.

![macOS](https://img.shields.io/badge/macOS-13.0+-blue)
![Swift](https://img.shields.io/badge/Swift-5.9+-orange)
![License](https://img.shields.io/badge/License-MIT-green)
![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-Optimized-purple)

## Features

- **100% Free & Open Source** - No subscriptions, no API costs, no hidden fees
- **Fully Offline** - All processing happens locally on your Mac using CoreML
- **Apple Silicon Optimized** - Uses WhisperKit with CoreML for blazing fast transcription on M1/M2/M3/M4
- **Push-to-Talk** - Hold Right Option key to record, release to transcribe
- **Auto-Paste** - Transcribed text is automatically pasted where your cursor is
- **Visual Feedback** - Elegant overlay with animated waveform during recording and pulsing dots during transcription
- **Media Control** - Optionally pause playing media while recording
- **Privacy First** - Your audio never leaves your device
- **Menu Bar App** - Runs quietly in the background, always accessible

## Demo

| Recording | Transcribing |
|-----------|--------------|
| Animated waveform bars | Pulsing dots indicator |

## Requirements

- **macOS 13.0** (Ventura) or later
- **Apple Silicon** (M1/M2/M3/M4) - Required for CoreML acceleration
- **~2GB disk space** - For the app and Whisper model (large-v3-turbo)

## Installation

### Download Release (Coming Soon)

Download the latest `.dmg` from the [Releases](https://github.com/zeffut/BetterFasterWhisper/releases) page.

### Build from Source

#### Prerequisites

- **Xcode 15+** with Command Line Tools
- macOS 13.0 or later

#### Build Steps

```bash
# Clone the repository
git clone https://github.com/zeffut/BetterFasterWhisper.git
cd BetterFasterWhisper

# Open in Xcode
open BetterFasterWhisper.xcodeproj

# Or build from command line
xcodebuild -project BetterFasterWhisper.xcodeproj \
           -scheme BetterFasterWhisper \
           -configuration Release \
           build

# The app bundle will be in DerivedData
```

#### Quick Deploy Script

```bash
# Build, deploy to /Applications, and launch
xcodebuild -project BetterFasterWhisper.xcodeproj -scheme BetterFasterWhisper -configuration Debug build
pkill -9 -f BetterFasterWhisper
cp -R ~/Library/Developer/Xcode/DerivedData/BetterFasterWhisper-*/Build/Products/Debug/BetterFasterWhisper.app /Applications/
open /Applications/BetterFasterWhisper.app
```

## Usage

### First Launch

1. **Launch the app** - It will appear in your menu bar (microphone icon)
2. **Grant permissions** when prompted:
   - **Microphone** - Required for recording audio
   - **Accessibility** - Required for auto-paste functionality
3. **Wait for model download** - The Whisper model (~1.5GB) will download automatically on first launch
4. **Start dictating!**

### How to Use

1. **Hold Right Option (`)** key to start recording
2. **Speak** - You'll see an animated waveform overlay
3. **Release** the key to stop recording
4. **Wait** - Pulsing dots indicate transcription in progress
5. **Done** - Text is automatically pasted at your cursor position

### Settings

Access settings from the menu bar icon:

- **Language** - Default transcription language (French by default)
- **Pause media when recording** - Automatically pause Spotify/Music/videos while recording

## Project Structure

```
BetterFasterWhisper/
├── App/
│   └── BetterFasterWhisper/
│       ├── Sources/
│       │   ├── App/
│       │   │   ├── BetterFasterWhisperApp.swift   # App entry point
│       │   │   └── AppDelegate.swift              # Push-to-talk, overlay, audio levels
│       │   ├── Core/
│       │   │   ├── Audio/
│       │   │   │   └── AudioRecorder.swift        # AVAudioEngine recording
│       │   │   ├── Models/
│       │   │   │   ├── AppState.swift             # Main app state (Observable)
│       │   │   │   ├── TranscriptionResult.swift
│       │   │   │   └── TranscriptionMode.swift
│       │   │   └── Services/
│       │   │       ├── WhisperService.swift       # WhisperKit integration
│       │   │       ├── ModelManager.swift         # Model download management
│       │   │       ├── HotkeyManager.swift        # Global hotkey handling
│       │   │       ├── ClipboardManager.swift     # Copy/paste operations
│       │   │       └── MediaControlManager.swift  # Pause/resume media
│       │   └── UI/Screens/
│       │       ├── MenuBarView.swift              # Menu bar dropdown
│       │       ├── SettingsView.swift             # Settings window
│       │       └── RecordingView.swift
│       ├── Assets.xcassets/
│       ├── Info.plist
│       └── BetterFasterWhisper.entitlements
├── whisper-core/                  # Rust library (unused in current version)
│   ├── src/
│   └── Cargo.toml
├── BetterFasterWhisper.xcodeproj
├── Package.swift
├── Scripts/
│   └── build.sh
├── LICENSE
└── README.md
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      Menu Bar App                            │
│  ┌─────────────────────────────────────────────────────┐    │
│  │              AppDelegate (NSApplicationDelegate)     │    │
│  │  - Push-to-talk (Right Option key via CGEvent)      │    │
│  │  - Audio level monitoring (AudioLevelManager)       │    │
│  │  - Overlay window (AudioWaveformOverlay)            │    │
│  └─────────────────────────────────────────────────────┘    │
│                            │                                 │
│  ┌─────────────────────────▼───────────────────────────┐    │
│  │                    AppState                          │    │
│  │           (Observable, @MainActor)                   │    │
│  │  - Recording state management                        │    │
│  │  - Transcription orchestration                       │    │
│  └───────────┬─────────────┬─────────────┬─────────────┘    │
│              │             │             │                   │
│  ┌───────────▼──┐ ┌────────▼────────┐ ┌─▼──────────────┐   │
│  │AudioRecorder │ │ WhisperService  │ │ClipboardManager│   │
│  │(AVAudioEngine)│ │  (WhisperKit)   │ │  (NSPasteboard)│   │
│  └──────────────┘ └────────┬────────┘ └────────────────┘   │
└────────────────────────────┼────────────────────────────────┘
                             │
                ┌────────────▼────────────┐
                │       WhisperKit        │
                │  (CoreML, Apple Silicon) │
                │  Model: large-v3-turbo  │
                └─────────────────────────┘
```

## Technology Stack

| Component | Technology |
|-----------|------------|
| UI Framework | SwiftUI |
| App Type | Menu Bar (LSUIElement) |
| Speech Recognition | [WhisperKit](https://github.com/argmaxinc/WhisperKit) by Argmax |
| ML Acceleration | CoreML (Apple Silicon) |
| Audio Recording | AVAudioEngine |
| Hotkey Detection | CGEvent (Carbon) |
| Media Control | MediaRemote.framework (private API) |
| Target | macOS 13.0+ |

## Model

BetterFasterWhisper uses the **large-v3-turbo** Whisper model via WhisperKit:

- **Size**: ~1.5GB
- **Performance**: Optimized for Apple Silicon via CoreML
- **Languages**: 100+ languages supported
- **Download**: Automatic on first launch

The model is downloaded to:
```
~/Library/Application Support/com.betterfasterwhisper/
```

## Permissions Required

| Permission | Reason |
|------------|--------|
| Microphone | Record audio for transcription |
| Accessibility | Simulate keyboard paste (Cmd+V) |

## Troubleshooting

### App doesn't respond to Right Option key
- Make sure Accessibility permission is granted in System Settings > Privacy & Security > Accessibility
- Try restarting the app after granting permission

### No transcription output
- Check that the model has finished downloading (menu bar shows status)
- Ensure microphone permission is granted

### Transcription is slow
- First transcription may be slower as the model loads into memory
- Subsequent transcriptions should be much faster

### View logs
```bash
/usr/bin/log show --predicate 'subsystem == "com.betterfasterwhisper"' --last 1m --info --style compact
```

## Roadmap

- [ ] Customizable hotkey
- [ ] Multiple language quick-switch
- [ ] Transcription history
- [ ] Custom vocabulary/corrections
- [ ] Smaller model options for faster transcription
- [ ] Voice activity detection (auto-stop)
- [ ] Audio input device selection
- [ ] Onboarding experience

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [OpenAI Whisper](https://github.com/openai/whisper) - The speech recognition model
- [WhisperKit](https://github.com/argmaxinc/WhisperKit) - Swift native Whisper implementation for Apple Silicon
- [SuperWhisper](https://superwhisper.com) - Inspiration for the user experience

## Disclaimer

This project is not affiliated with OpenAI, Argmax, or SuperWhisper. It's an independent open-source alternative built with love for the macOS community.

---

**Made with love for the open-source community**
