import SwiftUI
import SwiftData

/// The community side of the one player profile: nickname and look come from 我的; this screen
/// holds what is shared with gym members (visibility, consent, interests, public routines).
/// Presented as a sheet from the Community tab, or pushed from 我的 with `embedded: true`.
struct CommunityProfileView: View {
    @ObservedObject var store: GymStore
    let profile: UserProfile
    var embedded = false
    @Environment(\.dismiss) private var dismiss
    @Query private var workouts: [Workout]
    @Query private var exercises: [Exercise]
    @Query private var cardio: [CardioSession]
    @Query private var templates: [WorkoutTemplate]
    @AppStorage(TrainingPortraitFile.revisionKey) private var portraitRevision = 0
    @State private var portrait: UIImage?
    @State private var interests = ""
    @State private var visibility = "public"
    @State private var shareRank = false
    @State private var shareActivity = false
    @State private var bodyColor = "orange"
    @State private var publicIDs: Set<PersistentIdentifier> = []
    @State private var showPortrait = false
    @State private var saved = false

    private var gsr: Int {
        RankAggregator.overall(muscleScores: RankAggregator.muscleScores(bests: RankAggregator.exerciseBests(workouts: workouts, exercises: exercises, sex: profile.sex)))
    }
    /// How this player looks to members: the local look always wins over a truncated cloud copy.
    private var mine: SocialProfile {
        var me = SocialProfile(uid: store.uid, name: profile.name, gsr: gsr, cosmetics: profile.sharedCosmeticIDs, interests: interests, avatar: store.me?.avatar ?? AvatarAppearance())
        me.visibility = visibility
        return me
    }

    var body: some View {
        if embedded {
            form
        } else {
            NavigationStack {
                form.toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } } }
            }
        }
    }

    private var form: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    GymAvatarView(profile: mine, image: portrait ?? store.portraits[store.uid], size: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(profile.name).font(.headline)
                        Text("昵称和形象与「我的」一致，健身房成员看到的就是这个。").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Button { showPortrait = true } label: { Label("AI 肖像", systemImage: "photo") }
            } header: {
                Text("形象")
            }
            if store.connected {
                Section("健身房可见性") {
                    Picker("模式", selection: $visibility) { Text("公开").tag("public"); Text("匿名").tag("anonymous") }.pickerStyle(.segmented).accessibilityIdentifier("gymVisibility")
                    Text(visibility == "anonymous" ? "显示为通用头像，不展示资料，也不能收发新的好友请求；已有的对话保留在消息里。" : "健身房成员可以打开你的资料并申请加好友。").font(.caption).foregroundStyle(.secondary)
                }
                Section("共享资料") {
                    TextField("训练兴趣", text: $interests)
                    Toggle("分享我的段位与装备外观", isOn: $shareRank)
                    Toggle("分享训练亮点与活跃度", isOn: $shareActivity)
                    Picker("健身房小人颜色", selection: $bodyColor) {
                        Text("橙").tag("orange"); Text("蓝").tag("blue"); Text("紫").tag("purple"); Text("绿").tag("green")
                    }
                    Text("亮点包括最近训练类型、日期、时长、组数、七天肌群评分和六个月活跃度。体测、重量、次数和备注始终保密。").font(.caption).foregroundStyle(.secondary)
                }
                Section("公开训练计划") {
                    if templates.isEmpty { Text("在训练页新建计划后，可以在这里公开。").font(.caption) }
                    ForEach(templates) { routine in
                        Toggle(routine.name, isOn: Binding(get: { publicIDs.contains(routine.id) }, set: { if $0 { publicIDs.insert(routine.id) } else { publicIDs.remove(routine.id) } }))
                            .disabled(publicIDs.count >= 5 && !publicIDs.contains(routine.id))
                    }
                    Text("最多公开 5 个计划，只包含动作名称和计划组数/次数。保存后生效。").font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Button("保存社区资料") { save() }
                        .disabled(store.busy)
                        .accessibilityIdentifier("saveCommunityProfile")
                    if saved { Label("已保存", systemImage: "checkmark.circle.fill").foregroundStyle(.teal).accessibilityIdentifier("communityProfileSaved") }
                }
            } else if store.restoring {
                ProgressView("正在恢复社区资料…")
            } else {
                Section("加入社区") {
                    CommunityOnboardingCard(store: store, profile: profile, gsr: gsr)
                    if let error = store.restoreError {
                        Text(error).foregroundStyle(.orange)
                        Button("重试连接") { Task { await restore() } }
                    }
                }
            }
            if let error = store.error { Text(error).foregroundStyle(.orange) }
        }
        .navigationTitle("社区资料").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPortrait) { PortraitEditorView(profile: profile) }
        .task { await restore() }
        .task(id: portraitRevision) { portrait = TrainingPortraitFile.image() }
        .onChange(of: store.connected) { _, connected in if connected { loadDraft() } }
    }

    private func save() {
        store.perform {
            let shared = GymProfileSnapshot.routines(templates.filter { publicIDs.contains($0.id) }, exercises: exercises, selectedOnly: false)
            try await store.updateProfile(name: profile.name, interests: interests, shareRank: shareRank, gsr: gsr, cosmetics: profile.sharedCosmeticIDs,
                muscleRanks: GymProfileSnapshot.ranks(profile: profile, workouts: workouts, exercises: exercises), shareActivity: shareActivity,
                highlights: shareActivity ? GymProfileSnapshot.highlights(profile: profile, workouts: workouts, exercises: exercises, cardio: cardio) : nil, routines: shared, visibility: visibility)
            if var avatar = store.me?.avatar, avatar.color != bodyColor { avatar.color = bodyColor; try await store.saveAppearance(avatar) }
            for routine in templates { routine.isPublic = publicIDs.contains(routine.id) }
            try templates.first?.modelContext?.save()
            saved = true
        }
    }
    private func restore() async {
        if !store.connected { await store.restore() }
        loadDraft()
    }
    private func loadDraft() {
        interests = store.me?.interests ?? ""
        visibility = store.me?.visibility ?? "public"
        shareRank = store.sharesRank
        shareActivity = store.me?.shareActivity ?? false
        bodyColor = store.me?.avatar.color ?? "orange"
        publicIDs = Set(templates.filter(\.isPublic).map(\.id))
    }
}

/// First-time community setup. The nickname is the player's existing one; only consent and interests are asked.
struct CommunityOnboardingCard: View {
    @ObservedObject var store: GymStore
    let profile: UserProfile
    let gsr: Int
    @State private var interests = L("力量训练")
    @State private var shareRank = true
    @State private var consent = false

    var body: some View {
        Text("认识你的健身房伙伴").font(.title3.bold())
        Text("将以「\(profile.name)」的昵称和当前形象加入；昵称和形象在「我的」中修改。").font(.caption).foregroundStyle(.secondary)
        TextField("训练兴趣", text: $interests).textFieldStyle(.roundedBorder)
        Toggle("分享我的段位与装备外观", isOn: $shareRank).font(.subheadline)
        Toggle("向健身房成员公开这份资料", isOn: $consent).font(.subheadline).accessibilityIdentifier("gymProfileConsent")
        Text("只会公开昵称、兴趣、形象和你选择分享的段位信息。体测和训练历史保密。访客账号不含账号找回。")
            .font(.caption).foregroundStyle(.secondary)
        Button {
            store.perform { try await store.connect(name: profile.name, gsr: shareRank ? gsr : 0, cosmetics: shareRank ? profile.sharedCosmeticIDs : [], interests: interests, shareRank: shareRank) }
        } label: { Label("创建访客资料", systemImage: "arrow.right.circle.fill").frame(maxWidth: .infinity) }
            .buttonStyle(.borderedProminent).tint(.teal)
            .accessibilityIdentifier("createGuestProfile")
            .disabled(!consent || profile.name.trimmingCharacters(in: .whitespaces).isEmpty || store.busy || store.restoring)
    }
}
