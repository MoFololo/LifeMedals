import Foundation
import XCTest
@testable import LifeMedals

@MainActor
final class LocalImageStoreTests: XCTestCase {
    func testSaveReadAndRemoveDeviceLocalImage() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = LocalImageStore(rootDirectory: root)
        let id = UUID()
        let data = Data([0xFF, 0xD8, 0xFF, 0xD9])

        try store.save(data, kind: .evidence, id: id)

        XCTAssertTrue(store.contains(kind: .evidence, id: id))
        XCTAssertEqual(store.data(kind: .evidence, id: id), data)
        XCTAssertFalse(store.contains(kind: .taskSource, id: id))

        store.remove(kind: .evidence, id: id)
        XCTAssertFalse(store.contains(kind: .evidence, id: id))
    }

    func testEmptyImageIsRejected() {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = LocalImageStore(rootDirectory: root)

        XCTAssertThrowsError(try store.save(Data(), kind: .taskSource, id: UUID()))
    }
}
