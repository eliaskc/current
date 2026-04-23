import SwiftUI

// MARK: - Hover highlight modifier

/// Subtle tinted rounded-rect behind a borderless icon/control that lights up
/// on hover. Matches the Safari/Mail toolbar feel — the control's own frame
/// stays untouched, the highlight grows slightly past the edge so the glyph
/// doesn't feel cramped.
extension View {
    func hoverHighlight(cornerRadius: CGFloat = 5, expand: CGFloat = 3) -> some View {
        modifier(HoverHighlightModifier(cornerRadius: cornerRadius, expand: expand))
    }
}

private struct HoverHighlightModifier: ViewModifier {
    let cornerRadius: CGFloat
    let expand: CGFloat
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(hovering ? 0.09 : 0))
                    .padding(-expand)
            )
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

// MARK: - Chip button style

/// Flat neutral chip with clear hover + press states. Drop-in replacement for
/// `.bordered` on row controls (Skip / Update / Log toggle) where the system
/// style gave no visible hover feedback.
///
/// `prominent` bumps the resting fill so the row's primary action (Update)
/// reads louder than Skip without going full `.borderedProminent` blue.
struct ChipButtonStyle: ButtonStyle {
    var prominent: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        ChipBody(configuration: configuration, prominent: prominent)
    }

    private struct ChipBody: View {
        let configuration: ButtonStyle.Configuration
        let prominent: Bool
        @State private var hovering = false

        var body: some View {
            configuration.label
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(fillColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                )
                .contentShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
                .animation(.easeOut(duration: 0.07), value: configuration.isPressed)
        }

        private var fillColor: Color {
            let base = prominent ? 0.10 : 0.05
            let hoverBump = 0.06
            let pressBump = 0.10
            var opacity = base
            if hovering { opacity += hoverBump }
            if configuration.isPressed { opacity += pressBump }
            return Color.primary.opacity(opacity)
        }
    }
}
