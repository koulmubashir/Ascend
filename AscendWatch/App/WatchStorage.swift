import Foundation
import AscendKit

/// Local persistence for the Watch.
///
/// Without this the Watch held the plan in memory only, so quitting the app
/// lost it and the wrist was useless until the phone pushed again. A gym is
/// exactly where the phone is least likely to be reachable, so the Watch has to
/// stand on its own.
///
/// Also persists a session in progress: watchOS will terminate a backgrounded
/// app under memory pressure, and losing four logged sets because the app was
/// killed between exercises would be worse than any battery saving.
enum WatchStorage {

    private struct Snapshot: Codable {
        var plan: WatchSync.PlanSnapshot?
        var session: WatchSync.SessionSnapshot?
        var pendingLogs: [WatchSync.SetCompleted]
        var savedAt: Date
    }

    private static var url: URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("ascend-watch.json")
    }

    /// A session older than this is treated as abandoned rather than resumed.
    /// Coming back to a half-finished workout the next morning and being told
    /// you are mid-set would be worse than starting fresh.
    private static let staleAfter: TimeInterval = 6 * 3600

    static func save(
        plan: WatchSync.PlanSnapshot?,
        session: WatchSync.SessionSnapshot?,
        pendingLogs: [WatchSync.SetCompleted]
    ) {
        guard let url else { return }
        let snapshot = Snapshot(plan: plan, session: session,
                                pendingLogs: pendingLogs, savedAt: Date())
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
        } catch {
            // A lost write costs one restore, not the workout in front of you.
        }
    }

    struct Restored {
        var plan: WatchSync.PlanSnapshot?
        var session: WatchSync.SessionSnapshot?
        var pendingLogs: [WatchSync.SetCompleted]
    }

    static func load() -> Restored {
        guard let url,
              let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data)
        else { return Restored(plan: nil, session: nil, pendingLogs: []) }

        // The plan always comes back. The session only if it is recent enough
        // to plausibly still be the one you are in.
        let fresh = Date().timeIntervalSince(snapshot.savedAt) < staleAfter
        return Restored(
            plan: snapshot.plan,
            session: fresh ? snapshot.session : nil,
            pendingLogs: fresh ? snapshot.pendingLogs : []
        )
    }
}
