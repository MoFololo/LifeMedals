import Foundation
import SwiftData

/// A user's private discovery record. This model belongs exclusively to the
/// local SwiftData/CloudKit store and is never uploaded to the global monster
/// asset service.
@Model
final class MonsterDiscovery {
    var id: UUID = UUID()
    var canonicalTag: String = ""
    var displayName: String = ""
    var level: Int = 1
    var badgeKindRawValue: String = ""
    var variantID: String?
    var imageURL: String?
    var discoveredAt: Date = Date.now
    var sourceTaskID: UUID?
    /// App-level idempotency ledger for verified callbacks. Optional JSON keeps
    /// the public CloudKit schema additive and avoids a non-optional relation.
    var sourceTaskIDsJSON: String?
    var discoveryCount: Int = 1
    var styleVersion: String?

    init(
        id: UUID = UUID(),
        canonicalTag: String,
        displayName: String,
        level: Int,
        badgeKindRawValue: String,
        variantID: String? = nil,
        imageURL: String? = nil,
        discoveredAt: Date = .now,
        sourceTaskID: UUID? = nil,
        discoveryCount: Int = 1,
        styleVersion: String? = nil
    ) {
        self.id = id
        self.canonicalTag = canonicalTag
        self.displayName = displayName
        self.level = min(max(level, 1), 9)
        self.badgeKindRawValue = badgeKindRawValue
        self.variantID = variantID
        self.imageURL = imageURL
        self.discoveredAt = discoveredAt
        self.sourceTaskID = sourceTaskID
        if let sourceTaskID,
           let data = try? JSONEncoder().encode([sourceTaskID]) {
            self.sourceTaskIDsJSON = String(data: data, encoding: .utf8)
        }
        self.discoveryCount = max(discoveryCount, 1)
        self.styleVersion = styleVersion
    }

    /// Returns true only when this task represents a new encounter.
    func registerEncounter(sourceTaskID: UUID) -> Bool {
        var taskIDs = encounteredTaskIDs
        guard taskIDs.insert(sourceTaskID).inserted else { return false }
        if self.sourceTaskID == nil { self.sourceTaskID = sourceTaskID }
        if let data = try? JSONEncoder().encode(Array(taskIDs).sorted { $0.uuidString < $1.uuidString }) {
            sourceTaskIDsJSON = String(data: data, encoding: .utf8)
        }
        return true
    }

    private var encounteredTaskIDs: Set<UUID> {
        var result = Set<UUID>()
        if let sourceTaskID { result.insert(sourceTaskID) }
        if
            let sourceTaskIDsJSON,
            let data = sourceTaskIDsJSON.data(using: .utf8),
            let decoded = try? JSONDecoder().decode([UUID].self, from: data)
        {
            result.formUnion(decoded)
        }
        return result
    }
}
