import Foundation
import SwiftData

enum LocalImageKind: String, Sendable {
    case taskSource = "TaskSources"
    case evidence = "Evidence"
}

/// Stores private source and evidence images outside the CloudKit-backed
/// SwiftData store. Stable model UUIDs are the only link between cloud
/// metadata and a device-local image.
struct LocalImageStore: Sendable {
    static let shared = LocalImageStore()

    private let rootDirectory: URL

    init(rootDirectory: URL? = nil) {
        if let rootDirectory {
            self.rootDirectory = rootDirectory
        } else {
            let applicationSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? FileManager.default.temporaryDirectory
            self.rootDirectory = applicationSupport
                .appending(path: "LifeMedals", directoryHint: .isDirectory)
                .appending(path: "LocalImages", directoryHint: .isDirectory)
        }
    }

    func save(_ data: Data, kind: LocalImageKind, id: UUID) throws {
        guard !data.isEmpty else { throw LocalImageStoreError.emptyData }
        let directory = directory(for: kind)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try excludeFromBackup(directory)
        let destination = fileURL(for: kind, id: id)
        try data.write(to: destination, options: [.atomic, .completeFileProtection])
        try excludeFromBackup(destination)
    }

    func data(kind: LocalImageKind, id: UUID) -> Data? {
        let url = fileURL(for: kind, id: id)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try? Data(contentsOf: url, options: [.mappedIfSafe])
    }

    func remove(kind: LocalImageKind, id: UUID) {
        try? FileManager.default.removeItem(at: fileURL(for: kind, id: id))
    }

    func contains(kind: LocalImageKind, id: UUID) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(for: kind, id: id).path)
    }

    private func directory(for kind: LocalImageKind) -> URL {
        rootDirectory.appending(path: kind.rawValue, directoryHint: .isDirectory)
    }

    private func fileURL(for kind: LocalImageKind, id: UUID) -> URL {
        directory(for: kind).appending(path: id.uuidString.lowercased() + ".jpg")
    }

    private func excludeFromBackup(_ url: URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(values)
    }
}

enum LocalImageStoreError: LocalizedError {
    case emptyData

    var errorDescription: String? {
        L10n.text("图片数据为空。", english: "The image data is empty.")
    }
}

@MainActor
enum LocalImageMigration {
    /// Moves binary values written by older app versions out of the
    /// CloudKit-backed store. A legacy value is cleared only after the local
    /// atomic write succeeds, so migration never silently loses an image.
    static func migrateLegacyCloudImages(in context: ModelContext) {
        migrateLegacyCloudImages(in: context, store: .shared)
    }

    static func migrateLegacyCloudImages(in context: ModelContext, store: LocalImageStore) {
        var changed = false

        if let tasks = try? context.fetch(FetchDescriptor<TaskContract>()) {
            for task in tasks {
                guard let data = task.sourceImageData, !data.isEmpty else { continue }
                do {
                    try store.save(data, kind: .taskSource, id: task.id)
                    task.sourceImageData = nil
                    task.hadSourceImage = true
                    changed = true
                } catch {
                    assertionFailure("Could not migrate task source image: \(error)")
                }
            }
        }

        if let evidences = try? context.fetch(FetchDescriptor<Evidence>()) {
            for evidence in evidences {
                guard let data = evidence.imageData, !data.isEmpty else { continue }
                do {
                    try store.save(data, kind: .evidence, id: evidence.id)
                    evidence.imageData = nil
                    changed = true
                } catch {
                    assertionFailure("Could not migrate evidence image: \(error)")
                }
            }
        }

        if changed {
            do {
                try context.save()
            } catch {
                context.rollback()
                assertionFailure("Could not save local image migration: \(error)")
            }
        }
    }
}
