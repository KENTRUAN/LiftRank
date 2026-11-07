import XCTest
import SwiftData
@testable import LiftRank

final class StoreLoadingTests: XCTestCase {
    private enum LoadError: Error { case unavailable }

    @MainActor
    func testFailedAttemptsPreserveRecordsUntilRetrySucceeds() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("test.store")
        try seedStore(at: storeURL)
        var attempts = 0
        let loader = StoreLoader {
            attempts += 1
            guard attempts >= 3 else { throw LoadError.unavailable }
            return try self.makeContainer(at: storeURL)
        }

        XCTAssertNil(loader.container)
        XCTAssertEqual(attempts, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: storeURL.path))

        loader.retry()
        XCTAssertNil(loader.container)
        XCTAssertEqual(attempts, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: storeURL.path))

        loader.retry()
        let container = try XCTUnwrap(loader.container)
        let profiles = try container.mainContext.fetch(FetchDescriptor<UserProfile>())
        XCTAssertEqual(attempts, 3)
        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles.first?.name, "Existing lifter")
        XCTAssertEqual(profiles.first?.totalXP, 1234)
    }

    @MainActor
    func testSuccessfulLoadIsNotReplacedByRetry() throws {
        let schema = Schema([UserProfile.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        var attempts = 0
        let loader = StoreLoader {
            attempts += 1
            return container
        }

        loader.retry()

        XCTAssertTrue(loader.container === container)
        XCTAssertEqual(attempts, 1)
    }

    @MainActor
    private func seedStore(at url: URL) throws {
        let container = try makeContainer(at: url)
        let profile = UserProfile()
        profile.updateNickname("Existing lifter")
        profile.totalXP = 1234
        container.mainContext.insert(profile)
        try container.mainContext.save()
    }

    @MainActor
    private func makeContainer(at url: URL) throws -> ModelContainer {
        let schema = Schema([UserProfile.self])
        let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
