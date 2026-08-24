import Foundation
import AscendKit

/// iCloud backup of the whole store.
///
/// Uses the iCloud key-value store rather than CloudKit records. The reasoning:
/// this is one small JSON blob for one person, not a queryable multi-device
/// dataset, and KVS needs no schema, no record types and no conflict plumbing.
/// The tradeoff is a 1 MB ceiling per key - checked before writing, with a
/// clear failure rather than a silent drop.
///
/// It is a backup, not live sync: last writer wins, and the app only pulls when
/// the local store is empty or the user explicitly restores. Two phones editing
/// the same plan simultaneously is not a case this handles, and pretending
/// otherwise would lose data quietly.
@MainActor
final class CloudBackup: ObservableObject {

    @Published private(set) var lastSyncedAt: Date?
    @Published private(set) var lastError: String?

    private let store = NSUbiquitousKeyValueStore.default
    private let payloadKey = "gymtracker.snapshot"
    private let dateKey = "gymtracker.snapshotDate"

    /// KVS allows 1 MB per key. A long history of sets is nowhere near that,
    /// but it is checked rather than assumed.
    private let maxBytes = 900_000

    var isAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(externalChange),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store
        )
        store.synchronize()
        lastSyncedAt = store.object(forKey: dateKey) as? Date
    }

    @objc private func externalChange() {
        Task { @MainActor in
            lastSyncedAt = store.object(forKey: dateKey) as? Date
        }
    }

    enum Result: Equatable {
        case ok
        case notSignedIn
        case tooLarge(bytes: Int)
        case failed(String)
    }

    @discardableResult
    func upload(_ data: Data) -> Result {
        guard isAvailable else {
            lastError = "Sign in to iCloud to back up."
            return .notSignedIn
        }
        guard data.count <= maxBytes else {
            lastError = "Backup is too large for iCloud (\(data.count / 1024) KB)."
            return .tooLarge(bytes: data.count)
        }

        store.set(data, forKey: payloadKey)
        store.set(Date(), forKey: dateKey)
        guard store.synchronize() else {
            lastError = "iCloud rejected the write."
            return .failed("synchronize failed")
        }

        lastSyncedAt = Date()
        lastError = nil
        return .ok
    }

    /// The most recent backup, if there is one.
    func download() -> Data? {
        guard isAvailable else { return nil }
        store.synchronize()
        return store.data(forKey: payloadKey)
    }

    var remoteDate: Date? {
        store.object(forKey: dateKey) as? Date
    }
}
