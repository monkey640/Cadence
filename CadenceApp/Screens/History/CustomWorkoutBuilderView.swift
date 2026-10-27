import SwiftUI
import SwiftData
import CadenceCore

/// Build your own workout from the movement library (the glossary). Composes a
/// normal logged `TrainingSession` flagged `isCustom`, which lands in History and
/// logs/PRs like any session. Does not touch the plan or readiness loop.
struct CustomWorkoutBuilderView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var title = "Custom workout"
    @State private var date = Date()
    @State private var blocks: [DraftBlock] = []
    @State private var showLibrary = false

    struct DraftBlock: Identifiable {
        let id = UUID()
        let movement: MovementEntry
        var reps: Int
        var distance: Int?
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Workout") {
                    TextField("Title", text: $title)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }

                Section("Movements") {
                    if blocks.isEmpty {
                        Text("Add movements from the library below.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    ForEach($blocks) { $block in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(block.movement.name).font(.subheadline.weight(.medium))
                            Text(block.movement.short).font(.caption2).foregroundStyle(.secondary)
                                .lineLimit(2)
                            Stepper("Reps: \(block.reps)", value: $block.reps, in: 1...20)
                            HStack {
                                Text("Distance").foregroundStyle(.secondary)
                                Spacer()
                                TextField("m", text: distanceText($block))
                                    .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 70)
                                Text("m").foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { blocks.remove(atOffsets: $0) }

                    Button {
                        showLibrary = true
                    } label: {
                        Label("Add from library", systemImage: "plus.circle")
                    }
                }

                Section {
                    Text("Your own workout — not part of the vetted plan, and not adjusted by readiness. Logged for your record.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("New workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(blocks.isEmpty)
                }
            }
            .sheet(isPresented: $showLibrary) {
                MovementLibraryPicker { entry in
                    blocks.append(DraftBlock(movement: entry, reps: 4, distance: Self.defaultDistance(entry.movementID)))
                    showLibrary = false
                }
            }
        }
        .preferredColorScheme(Theme.scheme)
    }

    private func distanceText(_ block: Binding<DraftBlock>) -> Binding<String> {
        Binding(
            get: { block.wrappedValue.distance.map(String.init) ?? "" },
            set: { block.wrappedValue.distance = Int($0.trimmingCharacters(in: .whitespaces)) })
    }

    private func save() {
        let session = TrainingSession(
            date: date, title: title.isEmpty ? "Custom workout" : title,
            verdict: .hold, readinessScore: 0, volumeMultiplier: 1.0,
            wasAdjusted: false, isCustom: true)
        session.sets = blocks.enumerated().map { index, block in
            SessionSet(
                name: block.movement.name,
                order: index,
                plannedSets: block.reps,
                distanceMeters: block.distance.map { Double($0) },
                targetSeconds: nil,
                qualityRaw: Quality(rangesRaw: block.movement.movementID)?.rawValue,
                movementID: block.movement.movementID)
        }
        context.insert(session)
        try? context.save()
        dismiss()
    }

    /// Sensible starting distances by movement (editable). nil for warm-up/strength.
    static func defaultDistance(_ id: String) -> Int? {
        switch id {
        case "acceleration", "block_starts": return 30
        case "max_velocity": return 25
        case "speed_endurance": return 100
        case "special_endurance_1": return 200
        case "special_endurance_2": return 300
        case "extensive_tempo": return 100
        default: return nil
        }
    }
}

/// Picker over the bundled movement library.
private struct MovementLibraryPicker: View {
    let onPick: (MovementEntry) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(GlossaryStore.shared?.movements ?? []) { entry in
                Button {
                    onPick(entry)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.name).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                        Text(entry.develops).font(.caption2).foregroundStyle(.secondary)
                        Text(entry.short).font(.caption2).foregroundStyle(.tertiary).lineLimit(2)
                    }
                }
                .listRowBackground(Theme.card)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Movement library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
        .preferredColorScheme(Theme.scheme)
    }
}
