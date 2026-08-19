import SwiftUI

/// Conteúdo do painel de tradução — HIG: hierarquia clara, foco teclado, a11y.
struct TranslationResultPanelView: View {
    let original: String
    let translated: String
    let canReplace: Bool
    /// When false (read-only context), only the translation is shown — original is already on screen.
    let showOriginal: Bool
    let sourceLanguageLabel: String
    let targetLanguageLabel: String
    let pairContextLabel: String
    var onCopy: () -> Void
    var onReplace: () -> Void
    var onClose: () -> Void

    @State private var didCopy = false
    @State private var showOriginalExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var languagePairLabel: String {
        "\(sourceLanguageLabel) → \(targetLanguageLabel)"
    }

    var body: some View {
        panelContent
    }

    private var panelContent: some View {
        VStack(alignment: .leading, spacing: QTDesign.Spacing.s) {
            HStack(alignment: .center, spacing: QTDesign.Spacing.s) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(pairContextLabel)
                        .font(QTDesign.Fonts.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(languagePairLabel)
                        .font(QTDesign.Fonts.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    String(
                        format: String(localized: "%@, languages %@"),
                        pairContextLabel,
                        languagePairLabel
                    ))
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("Close")
                .accessibilityLabel("Close translation panel")
                .keyboardShortcut(.cancelAction)
            }

            ViewThatFits(in: .vertical) {
                textStack
                ScrollView {
                    textStack
                }
                .frame(maxHeight: 280)
            }

            HStack(spacing: QTDesign.Spacing.s) {
                Spacer(minLength: 0)
                Button {
                    onCopy()
                    didCopy = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        didCopy = false
                    }
                } label: {
                    Label(
                        didCopy ? "Copied" : "Copy",
                        systemImage: didCopy ? "checkmark" : "doc.on.doc")
                }
                .controlSize(.regular)
                .buttonStyle(.bordered)
                .frame(minHeight: 28)
                .keyboardShortcut("c", modifiers: [.command])
                .accessibilityLabel(didCopy ? "Copied" : "Copy translation")
                .accessibilityHint("Copies the translated text to the clipboard")
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: didCopy)

                if canReplace {
                    Button("Replace") {
                        onReplace()
                    }
                    .controlSize(.regular)
                    .buttonStyle(.borderedProminent)
                    .frame(minHeight: 28)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityLabel("Replace text in field")
                    .accessibilityHint("Replaces the selected text with the translation")
                }
            }
        }
        .padding(.horizontal, QTDesign.Spacing.l)
        .padding(.vertical, QTDesign.Spacing.m)
        .frame(minWidth: 360, idealWidth: 420, maxWidth: 520, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var textStack: some View {
        VStack(alignment: .leading, spacing: QTDesign.Spacing.s) {
            Text(translated)
                .font(QTDesign.Fonts.reading)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Translation")
                .accessibilityValue(translated)

            if showOriginal {
                DisclosureGroup(isExpanded: $showOriginalExpanded) {
                    Text(original)
                        .font(QTDesign.Fonts.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                        .accessibilityLabel("Original text")
                        .accessibilityValue(original)
                } label: {
                    Text("Show original")
                        .font(QTDesign.Fonts.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
