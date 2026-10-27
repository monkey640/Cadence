import Foundation
import SwiftData
import SwiftUI
import UIKit
import CadenceCore

/// Builds the on-device CSV export: sessions (with their sets) and the daily
/// readiness history. Written to a temp file and handed to the share sheet —
/// the athlete owns their data.
@MainActor
enum CSVExporter {

    static func export(context: ModelContext, now: Date = .now) -> URL? {
        var lines = ["section,date,title,type,readiness,verdict,multiplier,set_name,planned,completed,distance_m,best_time_s,pr"]

        let sessions = (try? context.fetch(
            FetchDescriptor<TrainingSession>(sortBy: [SortDescriptor(\.date, order: .forward)]))) ?? []
        for session in sessions {
            let base = [
                "session",
                iso(session.date),
                quote(session.title),
                session.isRecovery ? "recovery" : (session.isCustom ? "custom" : "plan"),
                session.hadCheckIn ? String(format: "%.0f", session.readinessScore) : "",
                session.hadCheckIn ? session.verdictRaw : "",
                String(format: "%.2f", session.volumeMultiplier),
            ]
            let sets = session.sets.sorted { $0.order < $1.order }
            if sets.isEmpty {
                lines.append((base + ["", "", "", "", "", ""]).joined(separator: ","))
            }
            for set in sets {
                lines.append((base + [
                    quote(set.name),
                    "\(set.plannedSets)",
                    "\(set.completedSets)",
                    set.distanceMeters.map { String(Int($0)) } ?? "",
                    set.bestTimeSeconds.map { String(format: "%.2f", $0) } ?? "",
                    set.wasPR ? "yes" : "",
                ]).joined(separator: ","))
            }
        }

        let readiness = (try? context.fetch(
            FetchDescriptor<DailyReadiness>(sortBy: [SortDescriptor(\.date, order: .forward)]))) ?? []
        for day in readiness {
            lines.append([
                "readiness", iso(day.date), "", "",
                String(format: "%.0f", day.score), day.verdictRaw,
                String(format: "%.2f", day.volumeMultiplier),
                "", "", "", "", "", "",
            ].joined(separator: ","))
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cadence-history-\(iso(now)).csv")
        do {
            try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    private static func iso(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func quote(_ text: String) -> String {
        "\"\(text.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

/// Thin wrapper over the system share sheet for the exported file.
struct CSVShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
