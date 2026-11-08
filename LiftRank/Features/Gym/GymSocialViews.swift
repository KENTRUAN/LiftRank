import SwiftUI
import SwiftData

struct GymFriendsView: View {
    @ObservedObject var store: GymStore
    let workout: String
    var embedded = false
    @Environment(\.dismiss) private var dismiss
    @State private var showTrainer = false
    @State private var selected: SocialProfile?
    @State private var chat: SocialProfile?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { showTrainer = true } label: {
                        HStack { Image(systemName: "sparkles").font(.title2).foregroundStyle(.teal); VStack(alignment: .leading) { Text("AI trainer").font(.headline); Text("Private · plans & workout todos").font(.caption).foregroundStyle(.secondary) } }
                    }.accessibilityIdentifier("trainerRecipient")
                }
                if store.friends.isEmpty { ContentUnavailableView("Your circle starts here", systemImage: "person.2", description: Text("Enter a gym and tap a member to send a friend request.")) }
                ForEach(["incoming", "accepted", "outgoing"], id: \.self) { status in
                    let group = store.friends.filter { $0.status == status }
                    if !group.isEmpty {
                        Section(status == "incoming" ? "Requests received" : status == "outgoing" ? "Requests sent" : "Friends & messages") {
                            ForEach(group) { friendship in
                                let profile = store.profiles[friendship.uid] ?? SocialProfile(uid: friendship.uid, name: "Private profile", gsr: 0, cosmetics: [], interests: "", avatar: AvatarAppearance())
                                Group {
                                    HStack {
                                        Button { if status == "accepted" { chat = profile } else { selected = profile } } label: {
                                            HStack {
                                                GymAvatarView(profile: profile, image: store.portraits[profile.uid])
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text(profile.name)
                                                    if status == "accepted", let message = store.latestMessages[profile.uid] {
                                                        Text(message.text).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                                    }
                                                }
                                                Spacer()
                                                if store.isUnread(profile.uid) { Circle().fill(.teal).frame(width: 8, height: 8).accessibilityLabel("Unread message") }
                                                Image(systemName: status == "accepted" ? "bubble.left" : "person.badge.clock")
                                            }
                                        }.buttonStyle(.plain).foregroundStyle(.primary).accessibilityIdentifier("gymFriend.\(profile.name)")
                                        if status == "incoming" {
                                            Button("Accept") { store.perform { try await store.api?.friendAction(target: profile.uid, action: "accept"); chat = profile } }.buttonStyle(.bordered).disabled(store.busy || store.anonymous || store.profiles[profile.uid] == nil)
                                        }
                                        if status == "accepted" {
                                            Button { selected = profile } label: { Image(systemName: "info.circle") }.buttonStyle(.borderless).accessibilityLabel("View profile")
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                if !store.blocked.isEmpty {
                    Section("Blocked members") {
                        ForEach(Array(store.blocked).sorted(), id: \.self) { id in
                            HStack { Text(store.profiles[id]?.name ?? "Blocked member"); Spacer(); Button("Unblock") { store.perform { try await store.api?.friendAction(target: id, action: "unblock") } } }
                        }
                    }
                }
                if let error = store.error { Text(error).foregroundStyle(.orange) }
            }
            .navigationTitle("Friends & inbox")
            .toolbar { if !embedded { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("gymInboxDone") } } }
            .sheet(isPresented: $showTrainer) { GymCompanionView(store: store, workout: workout) }
            .sheet(item: $selected) { profile in GymMemberView(store: store, memberID: profile.uid, workout: workout) }
            .sheet(item: $chat) { profile in GymChatView(store: store, target: profile.uid, isRoom: false, title: profile.name) }
        }
    }
}

struct GymMemberView: View {
    @ObservedObject var store: GymStore
    let memberID: String
    let workout: String
    @Environment(\.dismiss) private var dismiss
    @State private var showChat = false
    @State private var draft = ""
    @State private var generating = false
    @State private var error: String?
    @State private var blockConfirmation = false
    private var member: SocialProfile? { store.profiles[memberID] }
    private var friendship: Friendship? { store.friends.first { $0.uid == memberID } }
    private var mine: Bool { memberID == store.uid }
    private var unavailable: Bool { mine || store.offlineSample || store.blocked.contains(memberID) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    GymAvatarView(profile: member, image: store.portraits[memberID], size: 100)
                    Text(member?.name ?? "Gym member").font(.title.bold())
                    if let member, member.gsr > 0 {
                        HStack { Text("\(member.gsr) GSR").font(.headline); TierBadge(tier: RankTier.tier(for: member.gsr)) }
                        Text("Overall rank · shared by this member").font(.caption2).foregroundStyle(.secondary)
                    }
                    if member?.gsr == 0 { Text("Rank not shared yet").font(.caption).foregroundStyle(.secondary) }
                    if let interests = member?.interests, !interests.isEmpty { Text(interests).foregroundStyle(.secondary) }
                    if let presence = store.members.first(where: { $0.uid == memberID }) { Label("\(presence.station.capitalized) · \(presence.status)", systemImage: "figure.strengthtraining.traditional").font(.subheadline) }

                    if let member {
                        HStack { ForEach(member.cosmetics.compactMap(CosmeticCatalog.item).filter { $0.slot == .title }) { TitleTag(cosmetic: $0) } }
                    }
                    if mine { Text("This is how other gym members see you.").font(.callout).foregroundStyle(.secondary) }
                    else if store.offlineSample { Label("Simulated member · offline sample", systemImage: "info.circle").foregroundStyle(.orange) }
                    else if store.blocked.contains(memberID) { Text("You blocked this member."); action("Unblock", "unblock") }
                    else if member == nil || member?.visibility == "anonymous" { Text("This profile is private.").foregroundStyle(.secondary) }
                    else {
                        switch friendship?.status {
                        case "incoming": HStack { action("Accept request", "accept"); action("Decline", "decline") }
                        case "outgoing": Text("Friend request sent").foregroundStyle(.secondary); action("Cancel request", "cancel")
                        case "accepted":
                            Button { showChat = true } label: { Label("Open private chat", systemImage: "bubble.left.and.bubble.right.fill").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).tint(.teal)
                            action("Remove friend", "remove")
                        default:
                            action("Add friend", "request").disabled(!store.canRequestFriend(memberID))
                            if !store.canRequestFriend(memberID) { Text("Meet in the same checked-in gym to connect.").font(.caption).foregroundStyle(.secondary) }
                        }
                        Divider()
                        Button { makeIntroduction() } label: { Label(generating ? "Writing a draft…" : "Help me introduce myself", systemImage: "sparkles") }.disabled(generating)
                        if !draft.isEmpty {
                            Text("Your introduction · edit before sending").font(.caption).foregroundStyle(.secondary)
                            TextEditor(text: $draft).frame(height: 100).padding(6).overlay(RoundedRectangle(cornerRadius: 12).stroke(.secondary.opacity(0.3)))
                            Button("Send introduction") {
                                store.perform { try await store.api?.message(target: memberID, room: false, id: UUID().uuidString, text: draft); draft = ""; showChat = true }
                            }.buttonStyle(.borderedProminent).disabled(friendship?.status != "accepted" || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.busy)
                            if friendship?.status != "accepted" { Text("You can send this after your friend request is accepted.").font(.caption).foregroundStyle(.secondary) }
                        }
                        HStack {
                            Button(store.muted.contains(memberID) ? "Unmute room messages" : "Mute room messages") { store.toggleMute(memberID) }
                            Spacer()
                            Button("Block", role: .destructive) { blockConfirmation = true }
                        }.font(.caption)
                    }
                    if let member, member.visibility != "anonymous" { GymProfileHighlightsView(profile: member) }
                    if let error = error ?? store.error { Text(error).font(.caption).foregroundStyle(.orange) }
                }.padding(24)
            }
            .navigationTitle("Lifter profile").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("gymMemberDone") } }
            .sheet(isPresented: $showChat) { GymChatView(store: store, target: memberID, isRoom: false, title: member?.name ?? "Private chat") }
            .confirmationDialog("Block this member? This removes your friendship and private chat.", isPresented: $blockConfirmation, titleVisibility: .visible) {
                Button("Block member", role: .destructive) { store.perform { try await store.api?.friendAction(target: memberID, action: "block") } }
            }
        }
    }
    private func action(_ title: String, _ action: String) -> some View {
        Button(title) { store.perform { try await store.api?.friendAction(target: memberID, action: action) } }.buttonStyle(.bordered).disabled(store.busy || (action == "accept" && store.anonymous))
    }
    private func makeIntroduction() {
        guard !unavailable else { return }
        generating = true; error = nil
        Task {
            defer { generating = false }
            do { draft = try await store.api?.respond(messages: [["role": "user", "text": "Help me say hello to this member."]], workout: "", station: nil, targetID: memberID) ?? "" }
            catch { self.error = error.localizedDescription }
        }
    }
}

struct GymChatView: View {
    @ObservedObject var store: GymStore
    let target: String
    let isRoom: Bool
    let title: String
    @Environment(\.dismiss) private var dismiss
    @StateObject private var feed = GymChatFeed()
    @State private var input = ""
    @State private var sending = false
    @State private var error: String?
    @State private var pendingID: String?
    @State private var pendingText = ""
    private var available: Bool { isRoom ? store.membership?.roomId == target : store.friends.contains { $0.uid == target && $0.status == "accepted" } && !store.blocked.contains(target) }
    private var visible: [ChatMessage] { feed.messages.filter { !store.blocked.contains($0.senderID) && (!isRoom || !store.muted.contains($0.senderID)) } }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            if visible.isEmpty { Text("Say hello. A good training partner starts with a conversation.").font(.callout).foregroundStyle(.secondary).padding(30) }
                            ForEach(visible) { message in
                                HStack {
                                    if message.senderID == (isRoom ? store.roomIdentity : store.uid) { Spacer(minLength: 40) }
                                    VStack(alignment: .leading, spacing: 4) {
                                        if isRoom { Text(message.senderID.hasPrefix("anon-") ? "Anonymous lifter" : store.profiles[message.senderID]?.name ?? "Gym member").font(.caption.bold()) }
                                        Text(message.text)
                                    }.padding(12).background(message.senderID == (isRoom ? store.roomIdentity : store.uid) ? Color.teal.opacity(0.18) : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                                        .contextMenu {
                                            if message.senderID != (isRoom ? store.roomIdentity : store.uid) {
                                                Button("Report message", role: .destructive) { report(message) }
                                                if isRoom { Button("Mute member") { store.toggleMute(message.senderID) } }
                                            }
                                        }
                                    if message.senderID != (isRoom ? store.roomIdentity : store.uid) { Spacer(minLength: 40) }
                                }.id(message.id)
                            }
                        }.padding()
                    }
                    .onChange(of: feed.messages.count) { _, _ in
                        if let last = visible.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                        for message in feed.messages where !message.senderID.hasPrefix("anon-") { store.observeProfile(message.senderID) }
                    }
                }
                if let error = error ?? feed.error { Text(error).font(.caption).foregroundStyle(.orange).padding(8) }
                if !available { Text("This conversation is no longer available.").font(.caption).padding(8) }
                HStack {
                    TextField("Message", text: $input, axis: .vertical).lineLimit(1...4).textFieldStyle(.roundedBorder)
                    Button { send() } label: { if sending { ProgressView() } else { Image(systemName: "arrow.up.circle.fill").font(.title) } }
                        .accessibilityLabel("Send message")
                        .disabled(sending || !available || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || input.count > 1000)
                }.padding()
            }
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("gymChatDone") } }
            .onAppear {
                if !isRoom { store.openConversation = target; store.markRead(target) }
                let path = isRoom ? "roomMessages/\(target)" : "social/chats/\(GymStore.conversationID(store.uid, target))/messages"
                feed.start(path: path)
            }
            .onDisappear {
                feed.stop()
                if !isRoom, store.openConversation == target { store.markRead(target); store.openConversation = nil }
            }
            .onChange(of: available) { _, value in if !value { feed.stop() } }
        }
    }
    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if pendingText != text { pendingID = UUID().uuidString; pendingText = text }
        let id = pendingID ?? UUID().uuidString; pendingID = id
        sending = true; error = nil
        Task {
            defer { sending = false }
            do { try await store.api?.message(target: target, room: isRoom, id: id, text: text); input = ""; pendingID = nil; pendingText = "" }
            catch { self.error = error.localizedDescription }
        }
    }
    private func report(_ message: ChatMessage) {
        Task {
            do {
                var body: [String: Any] = ["targetID": message.senderID, "messageID": message.id]
                if isRoom { body["roomID"] = target }
                try await store.api?.send("reports", body: body)
                error = "Report received. You can also mute or block this member."
            } catch { self.error = error.localizedDescription }
        }
    }
}

struct GymCompanionView: View {
    @ObservedObject var store: GymStore
    let workout: String
    @Query private var profiles: [UserProfile]
    var body: some View {
        if let profile = profiles.first { TrainerConversationView(profile: profile).environmentObject(store) }
        else { Text("Your local profile is loading.") }
    }
}
