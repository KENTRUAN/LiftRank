import XCTest
@testable import LiftRank

final class GymTests: XCTestCase {
    @MainActor func testEquipmentRulesApplyToSceneAndReviewButNotOpenSpaces() throws {
        let store = GymStore()
        store.uid = "lifter"; store.room = .demo; store.station = "bench"
        store.members = [RoomPresence(uid: "lifter", sessionId: "session", x: 4, y: 3, station: "bench", status: "Ready", updatedAt: Date().timeIntervalSince1970 * 1000)]
        store.equipment["bench"] = try JSONDecoder().decode(GymEquipmentOccupancy.self, from: Data(#"{"ownerID":"lifter","members":{"lifter":"session"}}"#.utf8))
        XCTAssertTrue(store.requiresEquipmentForSets)
        XCTAssertNoThrow(try store.validateExerciseAtStation("bench_press"))
        XCTAssertThrowsError(try store.validateExerciseAtStation("pullup"))
        XCTAssertThrowsError(try store.validateExerciseAtStation("squat"))
        store.station = "rack"
        XCTAssertThrowsError(try store.validateExerciseAtStation("pullup"), "Must reserve the rack by tapping it first")
        store.equipment["rack"] = store.equipment["bench"]
        XCTAssertNoThrow(try store.validateExerciseAtStation("pullup"))
        store.members = []
        XCTAssertThrowsError(try store.validateExerciseAtStation("pullup"), "Expired/disconnected ownership cannot start a new set")
        store.startPrivateSpace(name: "Solo", gsr: 0, cosmetics: [])
        XCTAssertFalse(store.requiresEquipmentForSets)
        XCTAssertNoThrow(try store.validateExerciseAtStation("pullup"))
    }
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
        XCTAssertNil(profile.trainingAvatar)
    }

    func testTrainingAvatarSnapshotUsesSelectedMascotAndAccessoryPlacement() throws {
        let crown = RankAccessoryPlacement(offset: CGSize(width: 0.2, height: -0.1), rotation: 45, scale: 1.5)
        let data = try JSONEncoder().encode(["doubao.crown": crown, "crown": RankAccessoryPlacement(rotation: 90)])
        let selected = TrainingAvatarAppearance.snapshot(style: .doubao, accessory: "crown", savedPlacements: data)
        XCTAssertEqual(selected.mascotStyle, .doubao)
        XCTAssertEqual(selected.placement, crown)
        XCTAssertEqual(TrainingAvatarAppearance.snapshot(style: .nailong, accessory: "crown", savedPlacements: data).rotation, 90)
        XCTAssertEqual(TrainingAvatarAppearance.snapshot(style: .doubao, accessory: "glasses", savedPlacements: data).placement, RankAccessoryPlacement())
        let oldData = try JSONEncoder().encode(["crown": CGSize(width: -0.2, height: 0.3)])
        XCTAssertEqual(TrainingAvatarAppearance.snapshot(style: .nailong, accessory: "crown", savedPlacements: oldData).offsetX, -0.2)
    }

    func testSharedProfileCarriesOwnerAvatarAndHidesItWhenAnonymous() throws {
        let data = Data(#"{"uid":"other","name":"Other lifter","gsr":540,"cosmetics":["accessory.crown"],"trainingAvatar":{"style":"doubao","offsetX":0.2,"offsetY":-0.1,"rotation":45,"scale":1.5}}"#.utf8)
        var profile = try JSONDecoder().decode(SocialProfile.self, from: data)
        XCTAssertEqual(profile.visibleTrainingAvatar?.mascotStyle, .doubao)
        XCTAssertEqual(profile.visibleTrainingAvatar?.placement.offset.width, 0.2)
        XCTAssertEqual(AvatarSpec(ids: profile.cosmetics).accessory, "crown")
        let decoded = try JSONDecoder().decode(SocialProfile.self, from: JSONEncoder().encode(profile))
        XCTAssertEqual(profile.trainingAvatar, decoded.trainingAvatar)
        profile.visibility = "anonymous"
        XCTAssertNil(profile.visibleTrainingAvatar)
    }

    func testAvatarSnapshotBoundsInvalidLocalPlacementValues() {
        let appearance = TrainingAvatarAppearance(style: .nailong, placement: RankAccessoryPlacement(offset: CGSize(width: 3, height: -4), rotation: .infinity, scale: .nan))
        XCTAssertEqual(appearance.offsetX, 1); XCTAssertEqual(appearance.offsetY, -1)
        XCTAssertEqual(appearance.rotation, 0); XCTAssertEqual(appearance.scale, 1)
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
