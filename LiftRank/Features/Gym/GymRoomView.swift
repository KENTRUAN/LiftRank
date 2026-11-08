import SwiftUI
import SpriteKit

private enum GymRoomSheet: Identifiable {
    case member(String), chat(String), equipment(String), inbox, trainer, roomChat, workout(Workout), finish(Workout), setup(Workout), spaceSettings, cardioStart
    var id: String {
        switch self {
        case .member(let id): "member-\(id)"
        case .chat(let id): "chat-\(id)"
        case .equipment(let station): "equipment-\(station)"
        case .inbox: "inbox"
        case .trainer: "trainer"
        case .roomChat: "roomChat"
        case .workout: "workout"
        case .finish: "finish"
        case .setup: "setup"
        case .spaceSettings: "spaceSettings"
        case .cardioStart: "cardioStart"
        }
    }
}

struct GymRoomView: View {
    @ObservedObject var store: GymStore
    let gym: GymSummary
    let profile: UserProfile
    let session: Workout?
    let workoutSummary: String
    let startSession: () -> Void
    @StateObject private var scene = GymScene(size: GymScene.roomSize)
    @State private var sheet: GymRoomSheet?
    @State private var lastLogged: String?
    @State private var occupiedStation: String?
    @ScaledMetric(relativeTo: .caption) private var memberCardWidth: CGFloat = 90
    @State private var expanded = false
    private var plain: Bool { gym.isPlainSpace }
    private var online: Bool { !store.offlineSample && gym.isLocal != true }
    private var active: Workout? { session.flatMap { $0.isPublished ? nil : $0 } }

    var body: some View {
        roomPresentation
        .onAppear { scene.configure(plain: plain); wireScene(); syncScene() }
        .onReceive(store.$members) { _ in DispatchQueue.main.async { syncScene() } }
        .onReceive(store.$profiles) { _ in DispatchQueue.main.async { syncScene() } }
        .onReceive(store.$portraits) { _ in DispatchQueue.main.async { syncScene() } }
        .onChange(of: AppState.shared.pending) { _, action in if case .openWorkout = action { sheet = nil } }
        .onChange(of: store.blocked) { _, _ in syncScene() }
        .onChange(of: store.station) { _, _ in walkToReservedStation() }
        .onChange(of: store.equipment[store.station]?.ownerID) { _, _ in walkToReservedStation() }
        .task(id: active?.id) {
            if let active, !store.offlineSample {
                if AppState.shared.prefersCardioStart && active.cardioTimerStartedAt == nil {
                    AppState.shared.prefersCardioStart = false; sheet = .cardioStart
                } else if !active.startOptionsChosen && active.exercises.isEmpty { sheet = .setup(active) }
                else { await TrainingHealthManager.shared.start(active, context: active.modelContext) }
            }
        }
        .confirmationDialog("Equipment in use", isPresented: Binding(get: { occupiedStation != nil }, set: { if !$0 { occupiedStation = nil } }), titleVisibility: .visible) {
            if let station = occupiedStation, station != "cardio", store.occupants(station).count < 2 {
                Button("Ask to work in") { requestWorkIn(station, mode: "workIn") }
                Button("Ask to train together") { requestWorkIn(station, mode: "together") }
            }
            Button("Cancel", role: .cancel) { occupiedStation = nil }
        } message: {
            Text(occupiedStation == "cardio" ? "This cardio machine is occupied and cannot be shared." : "This station is occupied. The current lifter must accept before you can join.")
        }
        // Sheets and tab changes keep the room alive. Root handles background cleanup.
        .onDisappear { scene.cancelMovement() }
        .sheet(item: $sheet, onDismiss: {
            if let active, !active.startOptionsChosen && active.activity == .strength && active.exercises.isEmpty && !store.offlineSample {
                sheet = .setup(active)
            }
        }) { route in
            sheetContent(route).presentationDetents(detents(for: route)).presentationDragIndicator(.visible)
        }
    }
    private var roomPresentation: some View {
        roomContent
            .accessibilityIdentifier("gymRoomScroll")
            .background(Color(.systemGroupedBackground))
            .navigationTitle(gym.name).navigationBarTitleDisplayMode(.inline)
            .toolbar { roomToolbar }
            .safeAreaInset(edge: .top, spacing: 0) { socialBanner }
            .safeAreaInset(edge: .bottom, spacing: 0) { workoutControls }
    }
    private var roomContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                roomMap
                sessionDetails
            }
        }
    }
    private var roomMap: some View {
        VStack(spacing: 0) {
            roomStatus
            GymSceneView(scene: scene).frame(height: expanded ? 560 : 285)
                .accessibilityIdentifier("walkableGymScene")
                .accessibilityLabel(plain ? "Open workout space. Pinch to zoom, tap to walk, or use Start set below." : "Isometric gym. Pinch to zoom. Tap equipment to choose your station and exercise.")
            Text(plain ? "Tap to walk · Choose any workout below" : "Tap equipment to train · Tap a lifter to connect")
                .font(.subheadline.weight(.medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.93))
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.white.opacity(0.07))
            sceneControls
        }
        .background(Color(red: 0.055, green: 0.08, blue: 0.13))
    }
    private var roomStatus: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(plain ? "YOUR WORKOUT SPACE" : "LIFT / SOCIAL CLUB")
                    .font(.subheadline.bold()).foregroundStyle(.white)
                if !plain { Text("YOUR PEOPLE. YOUR PACE.").font(.caption).foregroundStyle(.mint) }
                HStack(spacing: 7) {
                    Circle().fill(store.offlineSample ? .orange : .mint).frame(width: 7, height: 7)
                        .accessibilityHidden(true)
                    Text(gym.isLocal == true ? "PRIVATE · ONLY ON THIS DEVICE" : store.offlineSample ? "OFFLINE SAMPLE · simulated members" : "LIVE · \(store.members.filter { $0.isFresh() }.count) in the room")
                        .font(.caption.bold()).foregroundStyle(.white.opacity(0.86))
                }
            }
            Spacer(minLength: 0)
            Button { scene.resetCamera() } label: {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.subheadline.bold())
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.10), in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .accessibilityLabel("Reset gym view")
            .accessibilityIdentifier("gymResetZoom")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
    private var sceneControls: some View {
        HStack(spacing: 18) {
            Text("Pinch to zoom · Drag with one finger when zoomed").font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button { scene.zoom(by: 0.8) } label: { Image(systemName: "minus.magnifyingglass") }.accessibilityLabel("Zoom out")
            Button { scene.zoom(by: 1.25) } label: { Image(systemName: "plus.magnifyingglass") }.accessibilityLabel("Zoom in")
            Button { expanded.toggle() } label: { Image(systemName: expanded ? "rectangle.compress.vertical" : "rectangle.expand.vertical") }
                .accessibilityLabel(expanded ? "Shrink gym" : "Enlarge gym")
        }.padding(12).background(.background)
    }
    private var sessionDetails: some View {
        VStack(spacing: 12) {
            workoutCard
            if plain {
                if let active, active.isOutdoor { OutdoorWorkoutMap(workout: active) }
            }
            if let active, !store.offlineSample { TrainingHealthStatusView(workout: active) }
            if let lastLogged { Label(lastLogged, systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.teal).accessibilityIdentifier("gymSetSaved") }
            HStack {
                Button { sheet = .trainer } label: { Label("AI trainer", systemImage: "sparkles") }
                Spacer()
                Button { sheet = .roomChat } label: { Label("Room chat", systemImage: "bubble.left.and.bubble.right") }.disabled(!online)
            }.buttonStyle(.bordered)
            memberList
            if let error = store.error { Text(error).font(.caption).foregroundStyle(.orange).accessibilityIdentifier("gymError") }
        }.padding(14)
    }
    @ToolbarContentBuilder private var roomToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) { Button("Leave") { store.suspend() } }
        if plain { ToolbarItem(placement: .primaryAction) { Button { sheet = .spaceSettings } label: { Image(systemName: "slider.horizontal.3") }.accessibilityLabel("Workout space settings") } }
        ToolbarItem(placement: .primaryAction) {
            Button { sheet = .inbox } label: {
                Label(store.inboxCount > 0 ? "Inbox (\(store.inboxCount))" : "Inbox", systemImage: "tray.fill")
            }.disabled(store.offlineSample).accessibilityIdentifier("gymInbox")
        }
    }
    @ViewBuilder private var workoutControls: some View {
        if !store.offlineSample {
            VStack(spacing: 10) {
                if !plain { equipmentControls }
                if let active { activeWorkoutControls(active) }
            }.padding(.horizontal, 16).padding(.vertical, 10).background(.regularMaterial)
        }
    }
    private var equipmentControls: some View {
        HStack {
            Label(store.station == "lounge" ? L("Tap equipment in the gym to choose a station") : GymEquipment.title(store.station), systemImage: "dumbbell.fill")
                .font(.caption).accessibilityIdentifier("gymCurrentStation")
            Spacer()
            if store.station != "lounge" {
                Button("Release equipment") { releaseEquipment() }.font(.caption.bold())
                    .disabled(store.busy || active?.hasPendingSet == true || active?.cardioTimerStartedAt != nil).accessibilityIdentifier("releaseEquipment")
            }
        }
    }
    @ViewBuilder private func activeWorkoutControls(_ workout: Workout) -> some View {
        if workout.activity != .strength {
            CardioTimerControls(workout: workout, profile: profile) { lastLogged = L("Cardio saved · elapsed time recorded"); if plain { store.suspend() } }
        } else {
            WorkoutSetControl(workout: workout, profile: profile, onStart: startSet,
                              onLog: { sheet = .equipment(plain ? "all" : store.station) },
                              onCardio: plain ? openCardio : nil)
        }
    }
    private func startSet() {
        if plain { sheet = .equipment("all") }
        else if store.ownsStation(store.station) { sheet = .equipment(store.station) }
        else { store.error = L("Tap equipment in the gym to choose a station first.") }
    }
    private func openCardio() { sheet = .cardioStart }
    private func detents(for route: GymRoomSheet) -> Set<PresentationDetent> {
        switch route {
        case .chat, .inbox, .trainer, .roomChat: [.medium, .large]
        default: [.large]
        }
    }
    @ViewBuilder private var socialBanner: some View {
        if let request = store.spaceRequests.first(where: { $0.roomId == gym.id }) {
            HStack {
                Text("\(request.name) wants to join this workout space").font(.caption.bold())
                Spacer()
                Button("Accept") { store.perform { try await store.respondToSpace(request, accept: true) } }.buttonStyle(.borderedProminent).accessibilityIdentifier("acceptSpaceRequest")
                Button("Decline") { store.perform { try await store.respondToSpace(request, accept: false) } }.font(.caption)
            }.padding(12).background(.regularMaterial).disabled(store.busy)
        } else if let (station, request) = store.incomingWorkIns.first {
            let name = store.roomProfile(request.requesterID)?.name ?? L("Gym member")
            let equipment = L(station.capitalized).lowercased(with: AppLanguage.current.locale)
            HStack {
                Text(request.mode == "workIn"
                     ? L("%@ asks to work in at the %@", name, equipment)
                     : L("%@ asks to train together at the %@", name, equipment))
                    .font(.caption.bold())
                Spacer()
                Button("Accept") { store.perform { try await store.equipmentAction(station, "accept", target: request.requesterID) } }.buttonStyle(.borderedProminent).accessibilityIdentifier("acceptWorkIn")
                Button("Decline") { store.perform { try await store.equipmentAction(station, "decline", target: request.requesterID) } }.font(.caption)
            }.padding(10).background(.regularMaterial)
        } else if let request = store.incomingRequests.first {
            HStack(spacing: 10) {
                Button { sheet = .member(request.uid) } label: {
                    Text("\(store.profiles[request.uid]?.name ?? "A lifter") wants to connect").font(.caption.bold()).multilineTextAlignment(.leading)
                }.foregroundStyle(.primary)
                Spacer(minLength: 0)
                Button("Accept & chat") {
                    store.perform {
                        try await store.api?.friendAction(target: request.uid, action: "accept")
                        sheet = .chat(request.uid)
                    }
                }.font(.caption.bold()).buttonStyle(.borderedProminent).tint(.teal).disabled(store.busy || store.anonymous || store.profiles[request.uid] == nil).accessibilityIdentifier("gymAcceptAndChat")
                Button { store.perform { try await store.api?.friendAction(target: request.uid, action: "decline") } } label: { Image(systemName: "xmark") }
                    .accessibilityLabel("Decline request").disabled(store.busy)
            }.padding(12).background(.regularMaterial)
        } else if let id = store.unreadFriends.first {
            Button { sheet = .chat(id) } label: {
                HStack { Label("New message · \(store.profiles[id]?.name ?? "Friend")", systemImage: "bubble.left.fill"); Spacer(); Text("Open") }
                    .font(.caption.bold()).padding(12).frame(maxWidth: .infinity).background(.regularMaterial)
            }.accessibilityIdentifier("gymMessageBanner")
        }
    }
    @ViewBuilder private var workoutCard: some View {
        if store.offlineSample {
            Text("Explore the room · workouts are saved in the live gym").font(.caption).foregroundStyle(.secondary)
        } else if let active {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(active.endedAt == nil ? "WORKOUT ACTIVE" : "WORKOUT STOPPED · REVIEW & FINISH").font(.caption2.bold()).foregroundStyle(.teal)
                        Text(active.title).font(.headline).lineLimit(1)
                    }
                    Spacer()
                    Group { if active.cardioTimerStartedAt != nil { CardioElapsedText(workout: active) } else if active.endedAt == nil { Text(active.startedAt, style: .timer) } else { Text(active.duration.clockString) } }.font(.callout.monospacedDigit())
                }
                HStack {
                    Text(active.activity == .strength ? "\(active.completedSets.count) sets saved" : "Elapsed time records automatically").font(.caption).accessibilityIdentifier("gymSessionSets")
                    Spacer()
                    Button("Review") { sheet = .workout(active) }.accessibilityIdentifier("gymReviewWorkout")
                    if active.activity == .strength { Button("Finish") { sheet = .finish(active) }.disabled(active.hasPendingSet).accessibilityIdentifier("gymFinishWorkout") }
                }.font(.subheadline)
            }.padding(12).background(.background, in: RoundedRectangle(cornerRadius: 16))
        } else {
            Button("Start another workout", action: startSession).buttonStyle(.bordered)
        }
    }
    private var memberList: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(store.members.filter { !store.blocked.contains($0.uid) }) { member in
                    if let p = store.roomProfile(member.uid) {
                        Button { openMember(p.uid) } label: {
                            VStack(spacing: 4) {
                                GymAvatarView(profile: p, image: member.visibility == "anonymous" ? nil : store.portraits[p.uid], size: 38)
                                Text(p.name).font(.caption)
                                Text(L(member.station.capitalized)).font(.caption2).foregroundStyle(.secondary)
                                Text(L(member.status)).font(.caption2).foregroundStyle(.teal)
                            }
                            .multilineTextAlignment(.center)
                            .frame(width: memberCardWidth)
                        }.buttonStyle(.plain).accessibilityIdentifier("gymMember.\(p.name)")
                    }
                }
            }
        }
    }
    @ViewBuilder private func sheetContent(_ route: GymRoomSheet) -> some View {
        switch route {
        case .member(let id): GymMemberView(store: store, memberID: id, workout: workoutSummary)
        case .chat(let id): GymChatView(store: store, target: id, isRoom: false, title: store.profiles[id]?.name ?? L("Private chat"))
        case .inbox: GymFriendsView(store: store, workout: workoutSummary)
        case .trainer: GymCompanionView(store: store, workout: workoutSummary)
        case .roomChat: GymChatView(store: store, target: gym.id, isRoom: true, title: L("Room chat"))
        case .spaceSettings: WorkoutSpaceSettings(store: store)
        case .cardioStart: CardioStartView(profile: profile) { _ in sheet = nil }
        case .equipment(let station):
            if station == "cardio" {
                if let active, active.activity != .strength, active.cardioTimerStartedAt != nil { TimedCardioWorkoutView(workout: active, profile: profile) }
                else { CardioStartView(profile: profile, requiresEquipment: true) { sheet = .workout($0) } }
            } else if let active {
                GymEquipmentSheet(workout: active, profile: profile, station: station, requiresEquipment: !plain) { name, rest in
                    lastLogged = L("%@ saved to your workout", name)
                    store.recordSetCompletion(Date())
                }
            }
        case .workout(let workout):
            ActiveWorkoutView(workout: workout, profile: profile).onDisappear {
                if plain && workout.isPublished { store.suspend() }
            }
        case .finish(let workout):
            FinishWorkoutSheet(workout: workout, profile: profile) { sheet = nil; lastLogged = L("Workout finished · saved to your history"); if plain { store.suspend() } }
        case .setup(let workout): WorkoutStartOptionsView(workout: workout, profile: profile)
        }
    }
    private func openMember(_ id: String) {
        if gym.isLocal == true { sheet = .spaceSettings; return }
        guard !id.hasPrefix("anon-"), store.members.first(where: { $0.uid == id })?.visibility != "anonymous" else { store.error = L("Anonymous lifter · profile hidden"); return }
        sheet = .member(id)
    }
    private func useEquipment(_ station: String) {
        guard !store.offlineSample else { return }
        if let active, active.activity != .strength, active.cardioTimerStartedAt != nil, station != "cardio" {
            store.error = L("End cardio before switching equipment."); return
        }
        guard active != nil || station == "cardio" else { store.error = L("Start a workout first."); return }
        guard station != "lounge" else { releaseEquipment(); return }
        if store.ownsStation(station) { walkToReservedStation(); sheet = .equipment(station); return }
        if active?.hasPendingSet == true { store.error = L("Finish your current set before switching equipment."); return }
        if !store.occupants(station).isEmpty { occupiedStation = station; return }
        store.perform {
            if store.station != "lounge" { try await store.equipmentAction(store.station, "release") }
            do { try await store.equipmentAction(station, "claim"); sheet = .equipment(station) }
            catch { store.error = error.localizedDescription }
        }
    }
    private func requestWorkIn(_ station: String, mode: String) {
        occupiedStation = nil
        store.perform {
            if store.station != "lounge" { try await store.equipmentAction(store.station, "release") }
            try await store.equipmentAction(station, "request", mode: mode)
            store.error = L("Request sent. Wait for the current lifter to accept.")
        }
    }
    private func walkToReservedStation() {
        scene.walkToStation(store.station, partner: store.equipment[store.station]?.ownerID != store.roomIdentity)
    }
    private func releaseEquipment() {
        guard active?.hasPendingSet != true, active?.cardioTimerStartedAt == nil else { store.error = L("End your current activity first."); return }
        if store.station != "lounge" { store.perform { try await store.equipmentAction(store.station, "release") } }
    }
    private func wireScene() {
        scene.onMove = { x, y in store.move(x: x, y: y) }
        scene.onProfile = { openMember($0) }
        scene.onTrainer = { sheet = .trainer }
        scene.onStation = { useEquipment($0) }
    }
    private func syncScene() {
        scene.sync(uid: store.roomIdentity, members: store.members.filter { !store.blocked.contains($0.uid) }, profiles: store.roomProfiles, portraits: store.portraits)
    }
}
