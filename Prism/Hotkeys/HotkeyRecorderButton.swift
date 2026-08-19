import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Button that records a global hotkey when clicked.
struct HotkeyRecorderButton: View {
    @EnvironmentObject private var appState: AppState
    @Binding var chord: HotkeyChord
    /// Other configured chords that must not collide with this one.
    var conflictingChords: [HotkeyChord] = []

    @State private var isRecording = false
    @State private var conflictMessage: String?

    /// Convenience for the previous single-chord API.
    init(chord: Binding<HotkeyChord>, otherChord: HotkeyChord? = nil) {
        self._chord = chord
        if let otherChord {
            self.conflictingChords = [otherChord]
        } else {
            self.conflictingChords = []
        }
    }

    init(chord: Binding<HotkeyChord>, conflictingChords: [HotkeyChord]) {
        self._chord = chord
        self.conflictingChords = conflictingChords
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Button {
                if isRecording {
                    finishRecording()
                } else {
                    beginRecording()
                }
            } label: {
                Text(isRecording ? "Press the shortcut…" : chord.displayString)
                    .font(.body.monospaced())
                    .frame(minWidth: 120)
            }
            .buttonStyle(.bordered)
            .tint(isRecording ? .accentColor : nil)
            .help(isRecording ? "Esc cancels" : "Click to record a new shortcut")

            if let conflictMessage {
                Text(conflictMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .onDisappear { finishRecording() }
    }

    private func beginRecording() {
        conflictMessage = nil
        isRecording = true
        appState.setHotkeyRecording(true)

        HotkeyRecordingMonitor.shared.begin { [appState] event in
            // Escape cancels without changing the chord.
            if event.keyCode == UInt16(kVK_Escape),
               event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
                DispatchQueue.main.async {
                    conflictMessage = nil
                    isRecording = false
                    appState.setHotkeyRecording(false)
                    HotkeyRecordingMonitor.shared.end()
                }
                return nil
            }

            guard let recorded = HotkeyChord.from(nsEvent: event) else {
                return nil
            }

            DispatchQueue.main.async {
                if conflictingChords.contains(recorded) {
                    conflictMessage = String(localized: "This shortcut is already in use.")
                } else {
                    chord = recorded
                    conflictMessage = nil
                }
                isRecording = false
                appState.setHotkeyRecording(false)
                HotkeyRecordingMonitor.shared.end()
            }
            return nil
        }
    }

    private func finishRecording() {
        isRecording = false
        appState.setHotkeyRecording(false)
        HotkeyRecordingMonitor.shared.end()
    }
}

/// Local key monitor used only while a HotkeyRecorderButton is recording.
private final class HotkeyRecordingMonitor {
    static let shared = HotkeyRecordingMonitor()

    private var monitor: Any?

    func begin(handler: @escaping (NSEvent) -> NSEvent?) {
        end()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: handler)
    }

    func end() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
