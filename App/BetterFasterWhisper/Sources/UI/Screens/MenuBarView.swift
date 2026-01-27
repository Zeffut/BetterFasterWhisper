//
//  MenuBarView.swift
//  BetterFasterWhisper
//
//  Created by BetterFasterWhisper Contributors
//  Licensed under MIT License
//

import SwiftUI

/// Menu bar dropdown content.
struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(spacing: 12) {
            // Header
            headerSection
            
            Divider()
            
            // Mode selector
            modeSelector
            
            Divider()
            
            // Status
            statusSection
            
            Divider()
            
            // Actions
            actionButtons
        }
        .padding()
        .frame(width: 280)
    }
    
    // MARK: - Sections
    
    private var headerSection: some View {
        HStack {
            Image(systemName: "waveform.circle.fill")
                .font(.title2)
                .foregroundStyle(.blue)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("BetterFasterWhisper")
                    .font(.headline)
                
                Text(appState.isEngineReady ? "Ready" : "Initializing...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Status indicator
            Circle()
                .fill(appState.isEngineReady ? .green : .orange)
                .frame(width: 8, height: 8)
        }
    }
    
    private var modeSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Mode")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 70))], spacing: 8) {
                ForEach(TranscriptionMode.allCases) { mode in
                    ModeButton(
                        mode: mode,
                        isSelected: appState.currentMode == mode
                    ) {
                        appState.setMode(mode)
                    }
                }
            }
        }
    }
    
    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            if appState.isRecording {
                HStack {
                    Circle()
                        .fill(.red)
                        .frame(width: 8, height: 8)
                    Text("Recording...")
                        .font(.caption)
                    Spacer()
                    Text(formatDuration(appState.recordingDuration))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            } else if appState.isTranscribing {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Transcribing...")
                        .font(.caption)
                }
            } else if let result = appState.lastTranscription {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Last transcription")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(result.text.prefix(100) + (result.text.count > 100 ? "..." : ""))
                        .font(.caption)
                        .lineLimit(2)
                }
            } else {
                Text("Press ⌥ Space to start recording")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private var actionButtons: some View {
        VStack(spacing: 8) {
            Button {
                appState.toggleRecording()
            } label: {
                Label(
                    appState.isRecording ? "Stop Recording" : "Start Recording",
                    systemImage: appState.isRecording ? "stop.circle.fill" : "mic.circle.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(appState.isRecording ? .red : .blue)
            .disabled(!appState.isEngineReady)
            
            HStack {
                SettingsButtonView()
                    .buttonStyle(.bordered)
                
                Spacer()
                
                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.bordered)
            }
        }
    }
    
    // MARK: - Helpers
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let tenths = Int((duration * 10).truncatingRemainder(dividingBy: 10))
        return String(format: "%d:%02d.%d", minutes, seconds, tenths)
    }
}

/// Button for selecting a transcription mode.
struct ModeButton: View {
    let mode: TranscriptionMode
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: mode.iconName)
                    .font(.title3)
                Text(mode.displayName)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

/// Settings button that works on macOS 13 and 14+
struct SettingsButtonView: View {
    var body: some View {
        if #available(macOS 14.0, *) {
            SettingsLink {
                Text("Settings")
            }
        } else {
            Button("Settings") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
        }
    }
}

#Preview {
    MenuBarView()
        .environmentObject(AppState.shared)
}
