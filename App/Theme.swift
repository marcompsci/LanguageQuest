import SwiftUI
import LQCore

extension Color {
    init(_ c: RGB) { self.init(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: 1) }
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = ThemePalette.of(.playful)
}

extension EnvironmentValues {
    var palette: ThemePalette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

extension View {
    /// Applies the age-sensitive theme. Text scale stacks on top of Dynamic Type.
    func lqTheme(_ p: ThemePalette, scale: Double) -> some View {
        self.environment(\.palette, p)
            .foregroundStyle(Color(p.text))
            .tint(Color(p.accent))
            .dynamicTypeSize(scale > 1.05 ? DynamicTypeSize.xLarge ... DynamicTypeSize.accessibility3
                                          : DynamicTypeSize.xSmall ... DynamicTypeSize.accessibility3)
    }
}

/// A big, friendly button. Minimum 54pt tall for small hands.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.palette) var p
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 54)
            .padding(.horizontal, 16)
            .background(Color(p.accent).opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(Color(p.onAccent))
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.palette) var p
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding(.horizontal, 16)
            .background(Color(p.surface).opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(p.accent), lineWidth: 2))
            .foregroundStyle(Color(p.text))
    }
}

struct Card<Content: View>: View {
    @Environment(\.palette) var p
    let content: Content
    init(@ViewBuilder _ c: () -> Content) { content = c() }
    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(p.surface), in: RoundedRectangle(cornerRadius: 16))
    }
}

/// Screen background for the active theme.
struct ThemedBackground: View {
    @Environment(\.palette) var p
    var body: some View { Color(p.background).ignoresSafeArea() }
}

/// A speaker button that plays Spanish audio.
struct SpeakerButton: View {
    @EnvironmentObject var model: AppModel
    let text: VText
    var label = "Play audio"
    var big = false
    var body: some View {
        Button { model.say(text) } label: {
            Image(systemName: "speaker.wave.2.fill")
                .font(big ? .system(size: 40) : .title3)
                .frame(minWidth: big ? 96 : 44, minHeight: big ? 96 : 44)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(label)
    }
}
