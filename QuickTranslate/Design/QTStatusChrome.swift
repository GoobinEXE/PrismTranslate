import SwiftUI

/// Chip de status compacto (idle / traduzindo / sucesso / erro) exibido no painel
/// do menu bar. Mesma fonte de verdade do ícone da barra (`AppState.status`).
struct QTStatusChip: View {
    let status: AppState.Status
    let isEnabled: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: iconName)
                .font(.system(size: 10, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .symbolEffect(.pulse, options: .repeating, isActive: isTranslating && !reduceMotion)
                .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
            Text(label)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(tint.opacity(0.14)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Status: \(label)")
    }

    private var isTranslating: Bool {
        status == .translating
    }

    private var label: String {
        switch status {
        case .idle: return isEnabled ? "Ativo" : "Pausado"
        case .translating: return "Traduzindo…"
        case .success: return "Concluído"
        case .error: return "Erro"
        }
    }

    private var iconName: String {
        switch status {
        case .idle: return isEnabled ? "circle.fill" : "pause.circle.fill"
        case .translating: return "ellipsis.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch status {
        case .idle: return isEnabled ? .green : .secondary
        case .translating: return .blue
        case .success: return .green
        case .error: return .red
        }
    }
}

/// Banner acionável (permissão faltando, último erro) com ícone, texto e ações.
struct QTBanner<Actions: View>: View {
    let icon: String
    let tint: Color
    let text: String
    var lineLimit: Int?
    private let actions: Actions

    init(
        icon: String,
        tint: Color,
        text: String,
        lineLimit: Int? = nil,
        @ViewBuilder actions: () -> Actions
    ) {
        self.icon = icon
        self.tint = tint
        self.text = text
        self.lineLimit = lineLimit
        self.actions = actions()
    }

    var body: some View {
        GlassSurface(cornerRadius: QTDesign.Radius.small) {
            VStack(alignment: .leading, spacing: QTDesign.Spacing.s) {
                HStack(alignment: .top, spacing: QTDesign.Spacing.s) {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tint)
                    Text(text)
                        .font(QTDesign.Fonts.caption)
                        .foregroundStyle(.primary.opacity(0.9))
                        .lineLimit(lineLimit)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                HStack(spacing: QTDesign.Spacing.s) {
                    Spacer(minLength: 0)
                    actions
                }
            }
            .padding(10)
        }
    }
}
