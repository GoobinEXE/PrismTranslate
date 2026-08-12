import SwiftUI

/// Conteúdo do painel de tradução. Aparência isolada aqui para mudanças visuais futuras.
struct TranslationResultPanelView: View {
    let original: String
    let translated: String
    let canReplace: Bool
    /// When false (read-only context), only the translation is shown — original is already on screen.
    let showOriginal: Bool
    let sourceLanguageLabel: String
    let targetLanguageLabel: String
    var onCopy: () -> Void
    var onReplace: () -> Void
    var onClose: () -> Void

    @State private var didCopy = false

    private var languagePairLabel: String {
        "\(sourceLanguageLabel) → \(targetLanguageLabel)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: QTDesign.Spacing.s) {
            HStack(alignment: .center, spacing: QTDesign.Spacing.s) {
                Text(languagePairLabel)
                    .font(QTDesign.Fonts.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .focusEffectDisabled()
                .help("Fechar")
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
                Button(didCopy ? "Copiado" : "Copiar") {
                    onCopy()
                    didCopy = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        didCopy = false
                    }
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
                .focusable(false)
                .focusEffectDisabled()
                .keyboardShortcut("c", modifiers: [.command])

                if canReplace {
                    Button("Substituir") {
                        onReplace()
                    }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
                    .focusable(false)
                    .focusEffectDisabled()
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(.horizontal, QTDesign.Spacing.l)
        .padding(.vertical, QTDesign.Spacing.m)
        .frame(width: 420, alignment: .topLeading)
        .fixedSize(horizontal: true, vertical: true)
        // Panel opens as key window; prevent any control from drawing the blue focus ring.
        .focusEffectDisabled()
    }

    private var textStack: some View {
        VStack(alignment: .leading, spacing: QTDesign.Spacing.s) {
            if showOriginal {
                Text(original)
                    .font(QTDesign.Fonts.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(translated)
                .font(.system(size: 17))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
