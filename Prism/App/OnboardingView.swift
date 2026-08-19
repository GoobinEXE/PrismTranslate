import AppKit
import Combine
import SwiftUI

struct OnboardingStep: Identifiable {
    let id: Int
    let title: String
    let subtitle: String
    let symbolName: String
    let symbolColor: Color
}

/// Wizard de configuração — 6 etapas com gates suaves: dá para continuar sem a
/// permissão, mas o estado pendente fica visível até o checklist final.
struct OnboardingView: View {
    var onClose: () -> Void

    @ObservedObject private var appState = AppState.shared

    @State private var stepIndex = 0
    @State private var accessibilityOK = Permissions.isAccessibilityTrusted()
    @State private var inputMonitoringOK = Permissions.isInputMonitoringGranted()
    @State private var packState: LanguagePackState = .checking
    @State private var didAutoAttemptDownload = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let timer = Timer.publish(every: 1.2, on: .main, in: .common).autoconnect()

    private let steps: [OnboardingStep] = [
        OnboardingStep(
            id: 0,
            title: String(localized: "Translate without leaving the field"),
            subtitle: String(localized:
                "Prism translates and replaces the focused field in any app — no extra windows, no copy and paste."),
            symbolName: "prism",
            symbolColor: .accentColor
        ),
        OnboardingStep(
            id: 1,
            title: String(localized: "Accessibility permission"),
            subtitle: String(localized:
                "This is what lets Prism read and replace the text you type. Without it, translation cannot run."),
            symbolName: "accessibility",
            symbolColor: .blue
        ),
        OnboardingStep(
            id: 2,
            title: String(localized: "Input Monitoring"),
            subtitle: String(localized:
                "Delivers global shortcuts even when another app is frontmost. Without it, ⌃⌥T looks like it “does nothing”."),
            symbolName: "keyboard",
            symbolColor: .orange
        ),
        OnboardingStep(
            id: 3,
            title: String(localized: "Language and translation"),
            subtitle: String(localized:
                "Choose the target language. With Apple Translation, packs download now and translation runs on this Mac."),
            symbolName: "character.bubble",
            symbolColor: .green
        ),
        OnboardingStep(
            id: 4,
            title: String(localized: "Shortcuts in practice"),
            subtitle: String(localized:
                "These are your current shortcuts. You can change them in Settings → Shortcuts."),
            symbolName: "command",
            symbolColor: .purple
        ),
        OnboardingStep(
            id: 5,
            title: String(localized: "You’re all set"),
            subtitle: String(localized:
                "Check the list — the prism icon stays in the menu bar to turn Prism on or off, change language, and open Settings."),
            symbolName: "checkmark.circle.fill",
            symbolColor: .green
        ),
    ]

    private var isLastStep: Bool { stepIndex >= steps.count - 1 }
    private var current: OnboardingStep { steps[stepIndex] }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            content
            footer
        }
        .frame(width: 480, height: 520)
        .background(windowBackground)
        .onAppear(perform: refreshPermissions)
        .onReceive(timer) { _ in
            refreshPermissions()
        }
        .onChange(of: appState.settings.outgoingTargetLanguage) { _, _ in
            didAutoAttemptDownload = false
            packState = .checking
            refreshLanguagePack()
        }
    }

    /// No Tahoe o material vem do NSGlassEffectView do controller; antes disso,
    /// vibrancy clássica.
    @ViewBuilder
    private var windowBackground: some View {
        if #available(macOS 26.0, *) {
            Color.clear
        } else {
            VisualEffectBackground()
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 10) {
            PrismGlyph()
                .frame(width: 16, height: 16)
                .foregroundStyle(.secondary)
            Text("Setup")
                .font(QTDesign.Fonts.heading)
                .foregroundStyle(.secondary)
            Spacer()
            Text(String(format: String(localized: "Step %lld of %lld"), Int64(stepIndex + 1), Int64(steps.count)))
                .font(QTDesign.Fonts.caption.weight(.medium))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                .accessibilityLabel(String(format: String(localized: "Step %lld of %lld"), Int64(stepIndex + 1), Int64(steps.count)))
        }
        .padding(.horizontal, QTDesign.Spacing.l)
        .padding(.vertical, 12)
    }

    // MARK: - Conteúdo

    private var content: some View {
        VStack(spacing: QTDesign.Spacing.l) {
            ZStack {
                Circle()
                    .fill(current.symbolColor.opacity(0.14))
                    .frame(width: 88, height: 88)
                if current.symbolName == "prism" {
                    PrismGlyph(lineWidth: 2.4)
                        .frame(width: 36, height: 36)
                        .foregroundStyle(current.symbolColor)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: current.symbolName)
                        .font(.largeTitle.weight(.medium))
                        .foregroundStyle(current.symbolColor)
                        .symbolRenderingMode(.hierarchical)
                        .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                        .accessibilityHidden(true)
                }
            }
            .padding(.top, 8)

            VStack(spacing: QTDesign.Spacing.s) {
                Text(current.title)
                    .font(QTDesign.Fonts.title)
                    .multilineTextAlignment(.center)

                Text(current.subtitle)
                    .font(QTDesign.Fonts.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 380)
            }
            .animation(stepAnimation, value: stepIndex)

            stepBody
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 4)
        }
        .padding(.horizontal, QTDesign.Spacing.xl)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var stepBody: some View {
        switch stepIndex {
        case 0:
            VStack(spacing: QTDesign.Spacing.s) {
                shortcutRow(
                    keys: appState.settings.translateOnlyHotkey.displayString,
                    label: "Translates and replaces in place"
                )
                shortcutRow(
                    keys: appState.settings.translateAndSendHotkey.displayString,
                    label: "Translates, replaces, and sends"
                )
            }
        case 1:
            VStack(spacing: QTDesign.Spacing.s) {
                permissionCard(
                    ok: accessibilityOK,
                    okTitle: "Accessibility granted",
                    pendingTitle: "Accessibility required"
                ) {
                    _ = Permissions.isAccessibilityTrusted(prompt: true)
                    Permissions.openAccessibilitySettings()
                    refreshPermissions()
                }
                if !accessibilityOK {
                    pendingBadge(
                        "You can continue and grant this later — translation only works with this permission."
                    )
                }
            }
        case 2:
            VStack(spacing: QTDesign.Spacing.s) {
                permissionCard(
                    ok: inputMonitoringOK,
                    okTitle: "Input Monitoring granted",
                    pendingTitle: "Input Monitoring required"
                ) {
                    _ = Permissions.requestInputMonitoring()
                    Permissions.openInputMonitoringSettings()
                    refreshPermissions()
                }
                if !inputMonitoringOK {
                    pendingBadge(
                        "Without it, global shortcuts stay inactive — the menu bar warns you when that happens."
                    )
                }
            }
        case 3:
            VStack(alignment: .leading, spacing: QTDesign.Spacing.s) {
                GlassSurface {
                    Picker(
                        "Target language (your messages)",
                        selection: Binding(
                            get: { appState.settings.outgoingTargetLanguage },
                            set: { appState.setOutgoingTargetLanguage($0) }
                        )
                    ) {
                        ForEach(LanguageCode.commonTargets) { language in
                            Text(language.displayName).tag(language.id)
                        }
                    }
                    .font(QTDesign.Fonts.body)
                    .padding(12)
                }
                languagePackCard
                QTSettingsLink(section: .provider) {
                    Label("Open Settings → Provider", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .font(QTDesign.Fonts.caption)
                .accessibilityLabel("Open Settings, Provider section")
                .accessibilityHint("Opens the Settings window on the Provider section")
                QTTipRow(
                    icon: "key.fill",
                    text:
                        "Prefer DeepL, Google, or LM Studio? Configure the engine in Settings → Provider."
                )
            }
            .onAppear(perform: refreshLanguagePack)
        case 4:
            VStack(spacing: QTDesign.Spacing.s) {
                shortcutRow(
                    keys: appState.settings.translateOnlyHotkey.displayString,
                    label: "Selects the field text, translates, and replaces"
                )
                shortcutRow(
                    keys: appState.settings.translateAndSendHotkey.displayString,
                    label: "Does the same and sends (Enter)"
                )
                if appState.settings.popupModeEnabled {
                    shortcutRow(
                        keys: appState.settings.popupHotkey.displayString,
                        label: "Shows the result in a panel (popup mode)"
                    )
                }
                shortcutRow(
                    keys: "⏎",
                    label: "Only if “Enter translates and sends” is on in the menu"
                )
                QTSettingsLink(section: .shortcuts) {
                    Label("Open Settings → Shortcuts", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .font(QTDesign.Fonts.caption)
                .accessibilityLabel("Open Settings, Shortcuts section")
                .accessibilityHint("Opens the Settings window on the Shortcuts section")
                .padding(.top, 4)
            }
        case 5:
            checklist
        default:
            EmptyView()
        }
    }

    // MARK: - Rodapé

    private var footer: some View {
        HStack(spacing: QTDesign.Spacing.m) {
            stepDots

            Spacer()

            if stepIndex == 0 {
                Button("Skip") {
                    // Vai ao checklist para ver o que ainda falta — não marca concluído.
                    go(to: steps.count - 1)
                }
                .foregroundStyle(.secondary)
                .help("Jumps to the final checklist without finishing the tutorial.")
                .accessibilityHint("Shows the checklist with pending items")
            } else {
                Button("Back") {
                    go(to: stepIndex - 1)
                }
            }

            if isLastStep {
                Button("Finish") {
                    finish()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            } else {
                Button(stepIndex == 0 ? "Get started" : "Continue") {
                    go(to: stepIndex + 1)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, QTDesign.Spacing.l)
        .padding(.vertical, 14)
        .controlSize(.regular)
    }

    private var stepDots: some View {
        HStack(spacing: 6) {
            ForEach(steps) { step in
                Capsule()
                    .fill(step.id == stepIndex ? Color.accentColor : Color.secondary.opacity(0.28))
                    .frame(width: step.id == stepIndex ? 16 : 6, height: 6)
            }
        }
        .animation(stepAnimation, value: stepIndex)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(format: String(localized: "Step %lld of %lld"), Int64(stepIndex + 1), Int64(steps.count)))
    }

    private var stepAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.22)
    }

    private func go(to index: Int) {
        if let animation = stepAnimation {
            withAnimation(animation) { stepIndex = index }
        } else {
            stepIndex = index
        }
        let step = steps[index]
        AccessibilityNotification.Announcement(
            String(format: String(localized: "Step %lld of %lld: %@"), Int64(index + 1), Int64(steps.count), step.title)
        ).post()
    }

    private func finish() {
        OnboardingController.markCompleted()
        onClose()
    }

    // MARK: - Componentes de etapa

    private func permissionCard(
        ok: Bool,
        okTitle: LocalizedStringKey,
        pendingTitle: LocalizedStringKey,
        openAction: @escaping () -> Void
    ) -> some View {
        GlassSurface {
            VStack(spacing: QTDesign.Spacing.m) {
                HStack(spacing: QTDesign.Spacing.s) {
                    Image(
                        systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(ok ? Color.green : Color.orange)
                    Text(ok ? okTitle : pendingTitle)
                        .font(QTDesign.Fonts.callout.weight(.medium))
                    Spacer(minLength: 0)
                }

                Button("Open System Settings…", action: openAction)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func pendingBadge(_ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
            Text(text)
                .font(QTDesign.Fonts.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func shortcutRow(keys: String, label: LocalizedStringKey) -> some View {
        GlassSurface(cornerRadius: QTDesign.Radius.small) {
            HStack {
                QTKeycap(keys: keys)
                Text(label)
                    .font(QTDesign.Fonts.callout)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Checklist final

    private var languagesReady: Bool {
        appState.settings.providerKind != .apple || packState == .installed
    }

    private var checklist: some View {
        VStack(alignment: .leading, spacing: QTDesign.Spacing.s) {
            GlassSurface {
                VStack(alignment: .leading, spacing: QTDesign.Spacing.s) {
                    checklistRow(ok: accessibilityOK, text: String(localized: "Accessibility")) {
                        Permissions.openAccessibilitySettings()
                    }
                    checklistRow(ok: inputMonitoringOK, text: String(localized: "Input Monitoring")) {
                        Permissions.openInputMonitoringSettings()
                    }
                    checklistRow(
                        ok: languagesReady,
                        text:
                            String(format: String(localized: "Translation languages (%@)"), LanguageCode.displayName(for: appState.settings.outgoingTargetLanguage)),
                        settingsSection: .general
                    )
                    checklistRow(ok: true, text: String(localized: "Prism icon in the menu bar"), fix: nil)
                }
                .padding(14)
            }

            if !accessibilityOK || !inputMonitoringOK {
                QTSettingsLink(section: .permissions) {
                    Label("Open Settings → Permissions", systemImage: "lock.shield")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .font(QTDesign.Fonts.caption)
                .accessibilityLabel("Open Settings, Permissions section")
                .accessibilityHint("Opens the Settings window on the Permissions section")
            }

            Text("Orange items are still pending — you can fix them now or later from the menu.")
                .font(QTDesign.Fonts.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func checklistRow(
        ok: Bool,
        text: String,
        settingsSection: SettingsSection? = nil,
        fix: (() -> Void)? = nil
    ) -> some View {
        HStack(spacing: QTDesign.Spacing.s) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(ok ? Color.green : Color.orange)
            Text(text)
                .font(QTDesign.Fonts.callout)
            Spacer(minLength: 0)
            if !ok {
                if let settingsSection {
                    QTSettingsLink(section: settingsSection) {
                        Text("Fix…")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                } else if let fix {
                    Button("Fix…", action: fix)
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(text): \(ok ? String(localized: "ready") : String(localized: "pending"))")
    }

    // MARK: - Language packs (Apple Translation)

    private var languagePackCard: some View {
        GlassSurface {
            VStack(spacing: QTDesign.Spacing.m) {
                HStack(spacing: QTDesign.Spacing.s) {
                    Image(systemName: packIconName)
                        .foregroundStyle(packIconColor)
                    Text(packTitle)
                        .font(QTDesign.Fonts.callout.weight(.medium))
                    Spacer(minLength: 0)
                    if packState == .checking || packState == .downloading {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if case .failed(let message) = packState {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if packState == .needsDownload || packState.isFailed {
                    Button(packState.isFailed ? "Try again" : "Download languages…") {
                        attemptLanguageDownload()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Button("Open Translation Languages in System Settings…") {
                        Permissions.openTranslationLanguagesSettings()
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .font(QTDesign.Fonts.caption)
                    .accessibilityHint("Opens System Settings to the translation languages list")
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var packTitle: String {
        let target = LanguageCode.displayName(for: appState.settings.outgoingTargetLanguage)
        switch packState {
        case .checking: return String(localized: "Checking languages…")
        case .installed: return String(format: String(localized: "Languages ready (target: %@)"), target)
        case .needsDownload: return String(format: String(localized: "Download needed (target: %@)"), target)
        case .downloading: return String(localized: "Downloading languages — confirm the system dialog")
        case .unsupported: return String(localized: "Language pair not supported — change the target or the provider")
        case .failed: return String(localized: "Download not completed")
        }
    }

    private var packIconName: String {
        switch packState {
        case .installed: return "checkmark.circle.fill"
        case .checking, .downloading: return "arrow.down.circle"
        case .needsDownload: return "exclamationmark.triangle.fill"
        case .unsupported, .failed: return "xmark.circle.fill"
        }
    }

    private var packIconColor: Color {
        switch packState {
        case .installed: return .green
        case .checking, .downloading: return .blue
        case .needsDownload: return .orange
        case .unsupported, .failed: return .red
        }
    }

    private func refreshLanguagePack() {
        guard stepIndex == 3 || stepIndex == 5, packState != .downloading else { return }
        Task { @MainActor in
            let settings = appState.settings
            let pair = AppleTranslationBridge.defaultPackPair(settings: settings)
            let state = await appState.appleBridge.languagePackState(
                from: pair.source,
                to: pair.target,
                ignoreCache: true
            )
            guard stepIndex == 3 || stepIndex == 5, packState != .downloading else { return }
            // Keep the failure visible until the pack actually installs or the user retries.
            if packState.isFailed && state != .installed { return }
            packState = state
            if state == .needsDownload && !didAutoAttemptDownload && stepIndex == 3 {
                attemptLanguageDownload()
            }
        }
    }

    private func attemptLanguageDownload() {
        didAutoAttemptDownload = true
        packState = .downloading
        Task { @MainActor in
            let settings = appState.settings
            let pair = AppleTranslationBridge.defaultPackPair(settings: settings)
            do {
                try await appState.appleBridge.ensureLanguagePacks(
                    from: pair.source,
                    to: pair.target
                )
                packState = .installed
            } catch {
                let current = await appState.appleBridge.languagePackState(
                    from: pair.source,
                    to: pair.target
                )
                packState = current == .installed ? .installed : .failed(error.localizedDescription)
            }
        }
    }

    private func refreshPermissions() {
        accessibilityOK = Permissions.isAccessibilityTrusted()
        inputMonitoringOK = Permissions.isInputMonitoringGranted()
        refreshLanguagePack()
    }
}

private struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
