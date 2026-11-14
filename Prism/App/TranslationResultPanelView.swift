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
    var targetLanguageCode: String = ""
    var notice: String? = nil
    /// Nil quando o painel não pode traduzir de novo (menu de idioma some).
    var onRetarget: ((String) -> Void)? = nil
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
                HStack(spacing: 6) {
                    languageChip
                    Text(pairContextLabel)
                        .font(QTDesign.Fonts.caption)
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
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

            if let notice {
                Label(notice, systemImage: "info.circle")
                    .font(QTDesign.Fonts.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
                copyButton

                if canReplace {
                    Button {
                        onReplace()
                    } label: {
                        HStack(spacing: 6) {
                            Text("Replace")
                            Text("⏎")
                                .font(.caption.monospaced())
                        }
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

    /// Em contexto somente leitura, Copiar é a ação principal (⏎); ao editar, Substituir assume.
    @ViewBuilder
    private var copyButton: some View {
        let button = Button {
            didCopy = true
            onCopy()
        } label: {
            HStack(spacing: 6) {
                Label(
                    didCopy ? "Copied" : "Copy",
                    systemImage: didCopy ? "checkmark" : "doc.on.doc")
                Text(canReplace ? "⌘C" : "⏎")
                    .font(.caption.monospaced())
                    // Sobre o fundo de destaque a dica mantém o contraste do rótulo.
                    .opacity(canReplace ? 0.6 : 1)
            }
        }
        .controlSize(.regular)
        .frame(minHeight: 28)
        .keyboardShortcut("c", modifiers: [.command])
        .accessibilityLabel(didCopy ? "Copied" : "Copy translation")
        .accessibilityHint("Copies the translation and closes the panel")
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: didCopy)

        if canReplace {
            button.buttonStyle(.bordered)
        } else {
            button.buttonStyle(.borderedProminent)
        }
    }

    /// Par de idiomas; com tradução disponível, vira menu para trocar o destino ali mesmo.
    @ViewBuilder
    private var languageChip: some View {
        let chip = HStack(spacing: 3) {
            Text(languagePairLabel)
            if onRetarget != nil {
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
            }
        }
        .font(QTDesign.Fonts.caption.weight(.semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(.fill.tertiary))

        if let onRetarget {
            Menu {
                ForEach(LanguageCode.commonTargets) { language in
                    Button {
                        onRetarget(language.id)
                    } label: {
                        if language.id == targetLanguageCode {
                            Label(language.displayName, systemImage: "checkmark")
                        } else {
                            Text(language.displayName)
                        }
                    }
                }
            } label: {
                chip
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Translate to another language")
            .accessibilityLabel(String(format: String(localized: "Target language: %@"), targetLanguageLabel))
        } else {
            chip
        }
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
