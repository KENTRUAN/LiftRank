import XCTest
@testable import LiftRank

final class GymTests: XCTestCase {
    func testPlainSpaceHasNoInvisibleEquipmentObstacles() {
        let start = GymLayout.Cell(x: 2, y: 7), target = GymLayout.Cell(x: 4, y: 2)
        XCTAssertTrue(GymLayout.path(from: start, to: target).isEmpty)
        XCTAssertEqual(GymLayout.path(from: start, to: target, plain: true).last, target)
        XCTAssertTrue(GymLayout.path(from: start, to: .init(x: 12, y: 5), plain: true).isEmpty)
    }
    func testCameraFitsSmallScreensAndBoundsPinchZoom() {
        XCTAssertEqual(GymCamera.fitScale(CGSize(width: 390, height: 360)), 2)
        XCTAssertEqual(GymCamera.zoom(0), 0.8)
        XCTAssertEqual(GymCamera.zoom(20), 3)
        XCTAssertEqual(GymCamera.zoom(.nan), 1)
    }
    @MainActor func testAllStartActionsGoToTheGymAndSelectItsTab() {
        let app = AppState(); app.communitySection = 1
        app.perform(.startTodayWorkout)
        XCTAssertEqual(app.tab, AppState.communityTab)
        XCTAssertEqual(app.communitySection, 0)
    }
    @MainActor func testOfflinePrivateSpacePublishesNoMembershipAndRetainsMovementAndState() {
        let store = GymStore()
        store.startPrivateSpace(name: "Solo", gsr: 400, cosmetics: [])
        XCTAssertTrue(store.room?.isLocal == true)
        XCTAssertNil(store.membership)
        XCTAssertFalse(store.offlineSample)
        store.move(x: 5, y: 4); store.setTrainingState("Training")
        XCTAssertEqual(store.members.first?.x, 5)
        XCTAssertEqual(store.members.first?.status, "Training")
        XCTAssertFalse(store.canRequestFriend("other"))
    }
    func testProfileDecodesRealtimeDatabaseOmittedEmptyArrays() throws {
        let data = Data(#"{"uid":"a","name":"Guest","gsr":0,"interests":"","avatar":{"preset":"bolt","color":"orange"}}"#.utf8)
        let profile = try JSONDecoder().decode(SocialProfile.self, from: data)
        XCTAssertEqual(profile.cosmetics, [])
        XCTAssertEqual(profile.avatar.preset, "bolt")
    }
    func testPathAvoidsEquipmentAndStaysOnGrid() {
        let start = GymLayout.Cell(x: 2, y: 7)
        let end = GymLayout.Cell(x: 9, y: 2)
        let path = GymLayout.path(from: start, to: end)
        XCTAssertEqual(path.last, end)
        var previous = start
        for cell in path {
            XCTAssertTrue(GymLayout.walkable(cell))
            XCTAssertEqual(abs(previous.x - cell.x) + abs(previous.y - cell.y), 1)
            previous = cell
        }
    }
    func testBlockedAndOutOfBoundsTargetsDoNotMove() {
        let start = GymLayout.Cell(x: 2, y: 7)
        XCTAssertTrue(GymLayout.path(from: start, to: .init(x: 4, y: 2)).isEmpty)
        XCTAssertTrue(GymLayout.path(from: start, to: .init(x: -1, y: 2)).isEmpty)
        XCTAssertTrue(GymLayout.path(from: start, to: start).isEmpty)
    }
    func testAllStationsReachable() {
        for target in GymLayout.stationCells.values {
            let start = GymLayout.Cell(x: 6, y: 8)
            XCTAssertEqual(GymLayout.path(from: start, to: target).last, target)
        }
    }
    func testPresenceExpiresAfter45Seconds() {
        let now = Date()
        let member = RoomPresence(uid: "a", sessionId: "s", x: 2, y: 7, station: "lounge", status: "Resting", updatedAt: now.timeIntervalSince1970 * 1000)
        XCTAssertTrue(member.isFresh(now: now.addingTimeInterval(44)))
        XCTAssertFalse(member.isFresh(now: now.addingTimeInterval(46)))
    }
    @MainActor
    func testConversationIdentityIsSymmetricAndUnambiguous() {
        XCTAssertEqual(GymStore.conversationID("a", "b"), GymStore.conversationID("b", "a"))
        XCTAssertNotEqual(GymStore.conversationID("ab", "c"), GymStore.conversationID("a", "bc"))
    }
    func testSocialProfileContainsNoPrivateHealthData() throws {
        let profile = SocialProfile(uid: "a", name: "Lifter", gsr: 500, cosmetics: [], interests: "Strength", avatar: AvatarAppearance())
        let json = try XCTUnwrap(String(data: JSONEncoder().encode(profile), encoding: .utf8))
        XCTAssertFalse(json.contains("bodyweight"))
        XCTAssertFalse(json.contains("birthday"))
        XCTAssertFalse(json.contains("workouts"))
    }
}
