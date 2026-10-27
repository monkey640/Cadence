import SwiftUI
import CadenceCore

/// A session block: compact headline by default, tap to reveal everything the
/// plan stores for it (full prescription + movement glossary). Fields that are
/// absent are simply omitted. Used by the plan overview/day previews.
struct SessionBlockRow: View {
    let block: TodayViewModel.DisplayBlock
    @State private var expanded = false

    private var glossary: MovementEntry? { GlossaryStore.entry(for: block.movementID) }
    private var canExpand: Bool { block.hasDetail || glossary != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                if canExpand { withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() } }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(headline).font(.title3).foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let rest = block.rest {
                            Text("Recovery: \(rest)").font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                        // Collapsed: the short cue (1–2 lines keeps the list calm).
                        if let g = glossary {
                            Text(g.short).font(.caption).foregroundStyle(Theme.textSecondary)
                                .lineLimit(expanded ? nil : 2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 8)
                    if canExpand {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(!canExpand)

            if expanded { expandedDetail }
        }
        .padding(.vertical, 6)
    }

    private var headline: String {
        guard let reps = block.scaledReps else { return block.name }
        var line = "\(reps) × \(block.name)"
        if let d = block.distanceM { line += " · \(d)m" }
        return line
    }

    @ViewBuilder private var expandedDetail: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Full plan prescription.
            VStack(alignment: .leading, spacing: 6) {
                if let intensity = block.intensity { row("Intensity", intensity) }
                if let sets = block.sets { row("Sets", "\(sets)") }
                if let reps = block.reps { row("Reps", "\(reps)") }
                if let d = block.distanceM { row("Distance", "\(d) m") }
                if let rest = block.rest { row("Rest", rest) }
                if let target = block.target { row("Target", target) }
                if let note = block.note, !note.isEmpty {
                    Text(note).font(.subheadline).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            // Full glossary content (only when this block maps to a movement).
            if let g = glossary { GlossaryDetail(entry: g) }
        }
    }

    private func row(_ key: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(key).font(.caption).foregroundStyle(Theme.textSecondary)
                .frame(width: 72, alignment: .leading)
            Text(value).font(.caption).foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

/// The movement glossary body — how to do it, what good feels like, common
/// mistakes, key cue. Shared by plan previews and the session player's how-to.
struct GlossaryDetail: View {
    let entry: MovementEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LaneLine()
            titled("Develops", entry.develops)
            titled("How to do it", entry.full.howToDoIt)
            titled("What good feels like", entry.full.whatGoodFeelsLike)
            VStack(alignment: .leading, spacing: 3) {
                Text("COMMON MISTAKES").font(.caption2.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                ForEach(entry.full.commonMistakes, id: \.self) { mistake in
                    Text("•  \(mistake)").font(.caption).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "key.fill").font(.caption2).foregroundStyle(Theme.brand)
                Text(entry.full.keyCue).font(.caption.weight(.medium)).foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func titled(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(Theme.textSecondary)
            Text(body).font(.caption).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
