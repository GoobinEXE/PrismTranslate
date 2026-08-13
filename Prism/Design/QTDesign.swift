import SwiftUI

/// Tokens de design compartilhados — raios, espaçamentos e tipografia semântica (HIG).
/// Mantém o visual consistente entre menu bar, Configurações e onboarding.
enum QTDesign {
    enum Radius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 18
        static let xl: CGFloat = 28
    }

    /// Tipografia semântica — escala com Dynamic Type / preferências do sistema.
    enum Fonts {
        static let title = Font.title3.weight(.semibold)
        static let heading = Font.headline
        static let body = Font.body
        static let caption = Font.caption
        static let callout = Font.callout
        /// Texto de leitura no painel de resultado.
        static let reading = Font.title3
        /// Chords/keycaps (⌃⌥T) — rounded para lembrar teclas físicas.
        static let keycap = Font.system(.body, design: .rounded).weight(.semibold)
    }
}

/// Tecla/atalho estilizado (ex.: ⌃⌥T) — usado em menu bar, onboarding e Configurações.
struct QTKeycap: View {
    let keys: String

    var body: some View {
        Text(keys)
            .font(QTDesign.Fonts.keycap)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.quaternary)
            )
            .accessibilityLabel("Atalho \(keys)")
    }
}

/// Linha de dica com ícone à esquerda.
struct QTTipRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(text)
                .font(QTDesign.Fonts.callout)
                .foregroundStyle(.primary.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
