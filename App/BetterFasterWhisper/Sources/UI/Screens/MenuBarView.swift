//
//  MenuBarView.swift
//  BetterFasterWhisper
//

import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var whisperService = WhisperService.shared
    @Environment(\.dismiss) private var dismiss

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
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    AppDelegate.shared?.openSettings()
                }
            } label: {
                Text("Settings")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

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

#Preview {
    MenuBarView()
        .environmentObject(AppState.shared)
}
