import SwiftUI

/// The color-scheme picker: live swatch tiles grouped dark / light. Tapping a
/// tile applies it instantly across the app. Mirrors the design mockup.
struct SchemePickerView: View {
    @Environment(ThemeManager.self) private var theme

    private var darkSchemes: [AppScheme] { AppScheme.allCases.filter(\.isDark) }
    private var lightSchemes: [AppScheme] { AppScheme.allCases.filter { !$0.isDark } }

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                section("Dark", darkSchemes)
                section("Light", lightSchemes)
            }
            .padding(20)
        }
        .cadenceBackground()
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func section(_ title: String, _ schemes: [AppScheme]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(2)
                .foregroundStyle(Theme.textSecondary)
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(schemes) { scheme in
                    SchemeTile(scheme: scheme, selected: theme.scheme == scheme) {
                        withAnimation(.easeInOut(duration: 0.25)) { theme.scheme = scheme }
                        Haptics.tick()
                    }
                }
            }
        }
    }
}

/// One swatch tile — a miniature of the readiness readout painted in the
/// scheme's own palette, so what you see is what the app becomes.
private struct SchemeTile: View {
    let scheme: AppScheme
    let selected: Bool
    let apply: () -> Void

    private var p: Palette { scheme.palette }

    var body: some View {
        Button(action: apply) {
            VStack(alignment: .leading, spacing: 0) {
                preview
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(scheme.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                        if selected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(Theme.brand)
                        }
                    }
                    Text(scheme.blurb)
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 10)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(scheme.name) theme\(selected ? ", selected" : "")")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    /// A tiny Today hero in this scheme's colors: label, score, verdict, a lane.
    private var preview: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("READINESS")
                    .font(.system(size: 7, weight: .semibold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundStyle(p.textSecondary)
                Spacer()
                Text("HOLD")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(p.hold)
            }
            Text("78")
                .font(.system(size: 40, weight: .black, design: .monospaced))
                .foregroundStyle(p.hold)
                .padding(.top, -2)
            // lane bar with baseline tick
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(p.surfaceSecondary).frame(height: 5)
                    Capsule().fill(p.backOff).frame(width: geo.size.width * 0.42, height: 5)
                    Rectangle().fill(p.textSecondary)
                        .frame(width: 1.5, height: 10)
                        .offset(x: geo.size.width * 0.66)
                }
            }
            .frame(height: 10)
        }
        .padding(12)
        .frame(height: 108)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(p.background)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(selected ? Theme.brand : p.laneLine, lineWidth: selected ? 2 : 1))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
