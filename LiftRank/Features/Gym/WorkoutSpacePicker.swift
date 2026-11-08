import SwiftUI

struct WorkoutSpacePicker: View {
    @ObservedObject var store: GymStore
    let startLocal: () -> Void
    let entered: () throws -> Void
    @State private var creating = false
    @State private var name = "My workout space"
    @State private var visibility = "private"
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if store.connected {
                SpaceInvitationList(store: store, entered: entered)
                HStack {
                    Text("Within 500 meters").font(.headline)
                    Spacer()
                    Button { Task { await store.discoverSpaces() } } label: { Image(systemName: "arrow.clockwise") }
                        .disabled(store.discovering).accessibilityLabel("Refresh nearby spaces")
                }
                if store.discovering { ProgressView("Finding gyms and spaces…") }
                ForEach(store.gyms) { gym in
                    Button { enter(gym) } label: { row(gym, action: "Start workout", symbol: "building.2.fill") }.buttonStyle(.plain)
                }
                ForEach(store.nearbySpaces) { gym in
                    VStack(alignment: .leading, spacing: 8) {
                        row(gym, action: "Public space", symbol: "person.2.fill")
                        if let request = store.sentSpaceRequests.first(where: { $0.gym.id == gym.id }) {
                            HStack {
                                Text(request.status == "declined" ? "Request declined" : "Waiting for approval").font(.caption)
                                Spacer()
                                Button("Cancel") { store.perform { try await store.cancelSpaceRequest(gym.id) } }
                            }
                        } else {
                            Button("Ask to join") { store.perform { try await store.requestSpace(gym) } }.buttonStyle(.bordered)
                        }
                    }.padding(12).background(.background, in: RoundedRectangle(cornerRadius: 16))
                }
                if let error = store.discoveryError { Text(error).font(.caption).foregroundStyle(.secondary) }
                else if !store.discovering && store.gyms.isEmpty && store.nearbySpaces.isEmpty {
                    Text("No gyms or public spaces nearby. Make a space of your own.").font(.subheadline).foregroundStyle(.secondary)
                }
                Button { creating = true } label: { Label("Create a workout space", systemImage: "plus.circle.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).tint(.teal).accessibilityIdentifier("createWorkoutSpace")
            }
            Button(action: startLocal) { Label("Private solo workout", systemImage: "lock.fill").frame(maxWidth: .infinity) }
                .buttonStyle(.bordered).accessibilityIdentifier("startPrivateWorkout")
            Text("A private solo space works offline. Nothing is shared.").font(.caption).foregroundStyle(.secondary)
        }
        .disabled(store.busy)
        .task(id: store.connected) { if store.connected { await store.discoverSpaces() } }
        .sheet(isPresented: $creating) {
            NavigationStack {
                Form {
                    TextField("Space name", text: $name).accessibilityIdentifier("workoutSpaceName")
                    Picker("Visibility", selection: $visibility) { Text("Private").tag("private"); Text("Public").tag("public") }.pickerStyle(.segmented)
                    Text(visibility == "public"
                         ? "People within 500 meters can find this space and ask to join. Any member can approve a request."
                         : "Hidden from nearby discovery. Invite friends; they must be within 500 meters to join.").font(.callout)
                    Text("Your exact location is used for proximity checks and is never shown to members.").font(.caption).foregroundStyle(.secondary)
                    Button("Create & start workout") {
                        store.perform {
                            try await store.createSpace(name: name, visibility: visibility)
                            do { try entered(); creating = false }
                            catch { await store.leave(); throw error }
                        }
                    }.disabled(store.busy || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 60).accessibilityIdentifier("confirmCreateSpace")
                    if store.busy { ProgressView() }
                    if let error = store.error { Text(error).foregroundStyle(.orange) }
                }.navigationTitle("New workout space").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { creating = false }.disabled(store.busy) } }
                    .interactiveDismissDisabled(store.busy)
            }
        }
    }
    private func row(_ gym: GymSummary, action: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.title2).foregroundStyle(.teal)
            VStack(alignment: .leading, spacing: 4) {
                Text(gym.name).font(.headline)
                Text(gym.kind == "custom" ? action : gym.address).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let distance = gym.distanceMeters { Text("\(Int(distance)) m").font(.caption.monospacedDigit()) }
        }.padding(.vertical, 6)
    }
    private func enter(_ gym: GymSummary) {
        store.perform {
            try await store.join(gym)
            do { try entered() } catch { await store.leave(); throw error }
        }
    }
}

struct SpaceInvitationList: View {
    @ObservedObject var store: GymStore
    let entered: () throws -> Void
    var body: some View {
        ForEach(store.spaceInvitations) { invitation in
            VStack(alignment: .leading, spacing: 8) {
                Text(invitation.gym.name).font(.headline)
                Text(invitation.status == "approved" ? "Your request was accepted" : "A friend invited you to train").font(.caption)
                HStack {
                    Button("Join nearby space") {
                        store.perform {
                            try await store.join(invitation.gym)
                            do { try entered(); AppState.shared.communitySection = 0; AppState.shared.tab = AppState.communityTab }
                            catch { await store.leave(); throw error }
                            await store.refreshSpaceInbox()
                        }
                    }.buttonStyle(.borderedProminent).accessibilityIdentifier("joinInvitedSpace")
                    Button("Dismiss") { store.perform { try await store.cancelSpaceRequest(invitation.gym.id) } }.buttonStyle(.bordered)
                }.disabled(store.busy)
            }.padding(12).background(.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

struct WorkoutSpaceSettings: View {
    @ObservedObject var store: GymStore
    @Environment(\.dismiss) private var dismiss
    @State private var sent: Set<String> = []
    var body: some View {
        NavigationStack {
            List {
                if store.room?.isLocal == true {
                    Label("Private · only on this device", systemImage: "lock.fill")
                    Text("Finish this workout to create a shared nearby space.").font(.caption)
                } else if store.room?.isHost == true {
                    Section("Space visibility") {
                        Picker("Visibility", selection: Binding(get: { store.room?.visibility ?? "private" }, set: { value in
                            store.perform { try await store.setSpaceVisibility(value) }
                        })) { Text("Public").tag("public"); Text("Private").tag("private") }.disabled(store.busy)
                        Text("Private spaces are hidden. Existing members stay when visibility changes.").font(.caption)
                    }
                    Section("Invite a nearby friend") {
                        ForEach(store.friends.filter { $0.status == "accepted" && !store.blocked.contains($0.uid) }) { friend in
                            HStack {
                                Text(store.profiles[friend.uid]?.name ?? L("Friend")); Spacer()
                                Button(sent.contains(friend.uid) ? "Invited" : "Invite") {
                                    store.perform { try await store.inviteToSpace(friend.uid); sent.insert(friend.uid) }
                                }.disabled(store.busy || sent.contains(friend.uid))
                            }
                        }
                        Text("Friends receive an invitation in Community and must be within 500 meters to join.").font(.caption)
                    }
                } else { Text("The host manages visibility and invitations. Any member can approve nearby join requests.") }
                if let error = store.error { Text(error).foregroundStyle(.orange) }
            }.navigationTitle("Workout space").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
    }
}
