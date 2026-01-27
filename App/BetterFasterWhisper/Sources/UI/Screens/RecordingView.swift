//
//  RecordingView.swift
//  BetterFasterWhisper
//
//  Created by BetterFasterWhisper Contributors
//  Licensed under MIT License
//

import SwiftUI

/// Floating recording panel shown during dictation.
struct RecordingView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(spacing: 16) {
            // Waveform visualization
            WaveformView(level: appState.audioLevel)
                .frame(height: 60)
            
            // Status text
            statusText
            
            // Duration
            Text(formatDuration(appState.recordingDuration))
                .font(.system(.title2, design: .monospaced))
                .foregroundStyle(.secondary)
            
            // Controls
            HStack(spacing: 20) {
                // Cancel button
                Button {
                    appState.cancelRecording()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
                
                // Stop button
                Button {
                    appState.stopRecording()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: [])
            }
            
            // Mode indicator
            HStack {
                Image(systemName: appState.currentMode.iconName)
                    .font(.caption)
                Text(appState.currentMode.displayName)
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 300)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    private var statusText: some View {
        Group {
            if appState.isRecording {
                HStack(spacing: 8) {
                    Circle()
                        .fill(.red)
                        .frame(width: 10, height: 10)
                        .opacity(pulsingOpacity)
                    Text("Recording")
                        .font(.headline)
                }
            } else if appState.isTranscribing {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Transcribing...")
                        .font(.headline)
                }
            } else if let result = appState.lastTranscription {
                VStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title)
                        .foregroundStyle(.green)
                    Text(result.text.isEmpty ? "No speech detected" : "Copied to clipboard")
                        .font(.subheadline)
                }
            } else {
                Text("Ready")
                    .font(.headline)
            }
        }
    }
    
    @State private var pulsingOpacity: Double = 1.0
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let tenths = Int((duration * 10).truncatingRemainder(dividingBy: 10))
        return String(format: "%d:%02d.%d", minutes, seconds, tenths)
    }
}

/// Simple waveform visualization.
struct WaveformView: View {
    let level: Float
    
    private let barCount = 30
    
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 2) {
                ForEach(0..<barCount, id: \.self) { index in
                    WaveformBar(
                        height: barHeight(for: index, in: geometry.size.height),
                        maxHeight: geometry.size.height
                    )
                }
            }
        }
    }
    
    private func barHeight(for index: Int, in maxHeight: CGFloat) -> CGFloat {
        // Create a wave pattern based on audio level
        let normalizedIndex = Double(index) / Double(barCount)
        let wave = sin(normalizedIndex * .pi * 2 + Date().timeIntervalSinceReferenceDate * 5)
        let baseHeight = maxHeight * 0.1
        let dynamicHeight = maxHeight * CGFloat(level) * 0.9 * CGFloat(abs(wave) * 0.5 + 0.5)
        return baseHeight + dynamicHeight
    }
}

struct WaveformBar: View {
    let height: CGFloat
    let maxHeight: CGFloat
    
    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(.blue.gradient)
            .frame(height: height)
            .frame(maxHeight: maxHeight, alignment: .center)
    }
}

#Preview {
    RecordingView()
        .environmentObject(AppState.shared)
        .frame(width: 400, height: 300)
        .background(.gray.opacity(0.3))
}
