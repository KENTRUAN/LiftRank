import SwiftUI
import SwiftData
import Speech
import AVFoundation

/// Natural-language editing of today's plan plus voice commands that drive the app.
struct CoachChatView: View {
    @Bindable var profile: UserProfile
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var plans: [DailyPlan]
    @Query private var exercises: [Exercise]
    @Query private var workouts: [Workout]
    @Query private var cardio: [CardioSession]
    @Query private var claims: [QuestClaim]
    @StateObject private var speech = SpeechRecognizer()
    @State private var messages: [AIChatMessage] = []
    @State private var input = ""
    @State private var sending = false
    @State private var error: String?
    @State private var showAvatar = false

    private var plan: DailyPlan? { plans.first { $0.dayKey == Date().dayKey } }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                planHeader
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            if messages.isEmpty { intro }
                            ForEach(messages) { m in bubble(m).id(m.id) }
                            if sending { HStack { ProgressView(); Text("思考中…").font(.caption).foregroundStyle(.secondary) }.padding(.horizontal) }
                            if let error { Text(error).font(.footnote).foregroundStyle(.red).padding(.horizontal) }
                        }.padding(.vertical)
                    }
                    .onChange(of: messages) { _, m in if let last = m.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } } }
                }
                inputBar
            }
            .navigationTitle("AI 训练助手")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { speech.stop(); dismiss() } } }
            .onChange(of: speech.transcript) { _, t in if speech.isRecording { input = t } }
            .sheet(isPresented: $showAvatar) { CoachAvatarView(profile: profile) }
        }
    }

    private var planHeader: some View {
        HStack(spacing: 12) {
            Button { showAvatar = true } label: {
                AvatarFigureView(spec: profile.coachAvatar, bust: true).frame(width: 56, height: 56).clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "pencil.circle.fill").font(.caption).foregroundStyle(Color.accentColor).background(Color(.systemBackground), in: Circle()).offset(x: 4, y: 4)
                    }
            }.buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 3) {
                Text(profile.coachName).font(.subheadline.bold())
                if let p = plan {
                    Text("今日训练：\(p.title)").font(.caption).foregroundStyle(.primary)
                    Text(p.items.map { "\($0.exerciseName) \($0.sets)×\($0.repsLow)–\($0.repsHigh)" }.joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                } else {
                    Text("今天还没有训练安排，可以让我帮你生成一份。").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
        .background(Color(.secondarySystemGroupedBackground))
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !AIBackend.isConfigured {
                Label("AI 服务暂未开通（此构建没有配置开发者接口）。点左上角头像仍可定义助手形象。", systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.orange)
            }
            Text("可以对 \(profile.coachName) 这样说：").font(.footnote).foregroundStyle(.secondary)
            ForEach(["把深蹲换成腿举，再加一组", "今天肩膀不舒服，去掉推举类动作", "改成 30 分钟的减脂训练", "开始今天的训练", "记录体重 74.5 公斤", "帮我记一次 5 公里跑步，30 分钟", "把你的头发改成蓝色，再戴个墨镜"], id: \.self) { s in
                Button { input = s } label: {
                    Text("“\(s)”").font(.subheadline).padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Color(.secondarySystemGroupedBackground), in: Capsule())
                }.buttonStyle(.plain)
            }
        }.padding(.horizontal)
    }

    private func bubble(_ m: AIChatMessage) -> some View {
        HStack(alignment: .bottom, spacing: 6) {
            if m.role == .user {
                Spacer(minLength: 40)
            } else {
                AvatarFigureView(spec: profile.coachAvatar, bust: true, showBackdrop: false).frame(width: 30, height: 30)
                    .background(Color(.tertiarySystemGroupedBackground), in: Circle()).clipShape(Circle())
            }
            Text(markdown(m.text)).font(.subheadline).padding(12)
                .background(m.role == .user ? Color.accentColor.opacity(0.18) : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            if m.role == .assistant { Spacer(minLength: 40) }
        }.padding(.horizontal)
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            Button { speech.isRecording ? speech.stop() : speech.start() } label: {
                Image(systemName: speech.isRecording ? "stop.circle.fill" : "mic.circle.fill").font(.system(size: 30))
                    .foregroundStyle(speech.isRecording ? .red : Color.accentColor)
            }
            TextField(speech.isRecording ? "正在聆听…" : "输入或按麦克风说话", text: $input, axis: .vertical).lineLimit(1...4)
                .padding(8).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            Button { send() } label: { Image(systemName: "arrow.up.circle.fill").font(.system(size: 30)) }
                .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || sending)
        }
        .padding(10)
        .background(.bar)
        .overlay(alignment: .top) {
            if let e = speech.error { Text(e).font(.caption2).foregroundStyle(.red).padding(4).background(.regularMaterial, in: Capsule()).offset(y: -24) }
        }
    }

    // MARK: - Send

    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        speech.stop()
        input = ""
        error = nil
        messages.append(AIChatMessage(role: .user, text: text))
        guard let config = AIBackend.config else { error = AIError.notConfigured.localizedDescription; return }
        sending = true
        let system = systemPrompt()
        let history = messages
        Task {
            do {
                let reply = try await AIService.complete(system: system, messages: history, config: config, maxTokens: 4096)
                handle(reply)
            } catch {
                self.error = error.localizedDescription
            }
            sending = false
        }
    }

    private func systemPrompt() -> String {
        let catalog = exercises.filter { !$0.isCardio }.map { "\($0.key)=\($0.name)/\($0.muscleGroup.name)/\($0.equipment.name)" }.joined(separator: ", ")
        let planJSON: String = {
            guard let p = plan, let data = try? JSONEncoder().encode(p.items.map(PlanItemDTO.init)), let s = String(data: data, encoding: .utf8) else { return "null" }
            return "{\"title\":\"\(p.title)\",\"items\":\(s)}"
        }()
        return """
        你是「段位健身」App 内的训练助手，名字叫「\(profile.coachName)」。\(profile.coachIntro.isEmpty ? "" : "你的形象设定：\(profile.coachIntro)。")帮助用户用自然语言修改今日训练，并可以直接调用 App 功能。用简体中文回答，简短友好。
        用户信息：\(profile.sex.label)，\(profile.age) 岁，体重 \(profile.bodyweightKg.fmt(1)) kg，目标 \(profile.planGoal.name)，器械 \(profile.planEquipment.name)，经验 \(profile.planExperience.name)，默认组间休息 \(profile.defaultRestSeconds) 秒。
        今日训练（JSON）：\(planJSON)
        可用动作库（key=名称/肌群/器械）：\(catalog)

        你必须只输出一个 JSON 对象，不要输出其他文字或代码块标记。格式：
        {"reply": "给用户看的回复（可用 Markdown 粗体与列表）",
         "plan": null 或 {"title": "训练名称", "items": [{"exerciseKey": "动作库中的 key", "sets": 3, "repsLow": 8, "repsHigh": 12, "restSeconds": 90}]},
         "actions": [] 或 [{"type": "start_workout"} | {"type": "open_tab", "tab": 0-4} | {"type": "log_weight", "kg": 74.5} | {"type": "add_cardio", "cardioType": "running|walking|hiking|cycling|swimming|rowing|elliptical|stairs|jumpRope|hiit|other", "minutes": 30, "distanceKm": 5} | {"type": "open_cardio"} | {"type": "set_avatar", "avatar": {"hair": "spiky", "hairColor": "blue", ...}, "name": "可选的新名字"}]}
        用户要求改变你（助手）的外观或名字时返回 set_avatar；avatar 只包含用户提到的字段，值必须从下面的选项里选：
        \(AvatarDescriber.optionList)
        规则：只有当用户要求修改/生成训练时才返回 plan（返回完整的新 items 列表，而不是差异）；exerciseKey 必须来自动作库。
        tab 对应：0 训练，1 段位，2 奖励，3 饮食，4 我的。用户说"开始训练"时返回 start_workout；说"记录体重 X"时返回 log_weight（单位换算为公斤）；说记录跑步/骑行等时返回 add_cardio。
        不确定时在 reply 中追问，并让 plan 为 null、actions 为空。
        """
    }

    private func handle(_ raw: String) {
        guard let obj = AIJSON.extractObject(from: raw) else {
            messages.append(AIChatMessage(role: .assistant, text: raw))
            return
        }
        var notes: [String] = []
        if let planObj = obj["plan"] as? [String: Any], let items = planObj["items"] as? [[String: Any]] {
            let byKey = Dictionary(uniqueKeysWithValues: exercises.map { ($0.key, $0) })
            let byName = Dictionary(exercises.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
            var newItems: [TemplateExercise] = []
            for it in items {
                let key = it["exerciseKey"] as? String ?? ""
                guard let ex = byKey[key] ?? byName[it["exerciseName"] as? String ?? ""] else { continue }
                let sets = max(1, min(10, it["sets"] as? Int ?? 3))
                let low = max(1, min(50, it["repsLow"] as? Int ?? 8))
                let high = max(low, min(50, it["repsHigh"] as? Int ?? low))
                let rest = max(0, min(600, it["restSeconds"] as? Int ?? profile.defaultRestSeconds))
                newItems.append(TemplateExercise(exerciseKey: ex.key, exerciseName: ex.name, sets: sets, repsLow: low, repsHigh: high, restSeconds: rest))
            }
            if !newItems.isEmpty {
                let title = (planObj["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? plan?.title ?? "今日训练"
                if let p = plan { p.title = title; p.items = newItems; p.sourceRaw = "ai" } else {
                    context.insert(DailyPlan(dayKey: Date().dayKey, title: title, items: newItems, source: "ai"))
                }
                try? context.save()
                notes.append("已更新今日训练（\(newItems.count) 个动作）")
            }
        }
        if let actions = obj["actions"] as? [[String: Any]] {
            for a in actions { if let n = perform(a) { notes.append(n) } }
        }
        var reply = obj["reply"] as? String ?? "好的。"
        if !notes.isEmpty { reply += "\n\n" + notes.map { "✅ " + $0 }.joined(separator: "\n") }
        messages.append(AIChatMessage(role: .assistant, text: reply))
    }

    private func perform(_ a: [String: Any]) -> String? {
        switch a["type"] as? String {
        case "start_workout":
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { AppState.shared.perform(.startTodayWorkout) }
            return "正在开始今日训练"
        case "open_tab":
            if let t = a["tab"] as? Int, (0...4).contains(t) { dismiss(); AppState.shared.perform(.openTab(t)); return "已切换页面" }
        case "open_cardio":
            dismiss(); AppState.shared.perform(.openCardio); return "已打开有氧记录"
        case "set_avatar":
            let base = profile.coachAvatarIDs.isEmpty ? AvatarSpec.defaultCoachIDs : profile.coachAvatarIDs
            var changed = false
            if let obj = a["avatar"] as? [String: Any] {
                let ids = AvatarDescriber.ids(from: obj, base: base)
                if ids != base { profile.coachAvatarIDs = ids; changed = true }
            }
            if let n = a["name"] as? String, !n.trimmingCharacters(in: .whitespaces).isEmpty { profile.coachName = n.trimmingCharacters(in: .whitespaces); changed = true }
            guard changed else { break }
            try? context.save()
            return "已更新 \(profile.coachName) 的形象"
        case "log_weight":
            if let kg = (a["kg"] as? Double) ?? (a["kg"] as? Int).map(Double.init), kg > 20, kg < 400 {
                context.insert(BodyMeasurement(date: Date(), metric: .weight, value: kg))
                profile.bodyweightKg = kg
                try? context.save()
                return "已记录体重 \(kg.fmt(1)) kg"
            }
        case "add_cardio":
            let type = CardioType(rawValue: a["cardioType"] as? String ?? "") ?? .other
            let minutes = (a["minutes"] as? Double) ?? (a["minutes"] as? Int).map(Double.init) ?? 0
            let km = (a["distanceKm"] as? Double) ?? (a["distanceKm"] as? Int).map(Double.init) ?? 0
            guard minutes > 0 else { break }
            let s = CardioSession(date: Date(), type: type, durationMinutes: minutes, distanceKm: km,
                                  calories: (type.metValue * profile.bodyweightKg * minutes / 60).rounded())
            context.insert(s)
            try? context.save()
            let gsr = RankAggregator.overall(muscleScores: RankAggregator.muscleScores(bests: RankAggregator.exerciseBests(workouts: workouts, exercises: exercises, sex: profile.sex)))
            let eggs = DailyTrainingEngine.claimIfEarned(profile: profile, workouts: workouts, cardio: cardio + [s], claims: claims, gsr: gsr, context: context)
            return "已记录 \(type.name) \(minutes.fmt(0)) 分钟" + (eggs > 0 ? "，今日训练奖励 +\(eggs) Eggs" : "")
        default: break
        }
        return nil
    }
}

private struct PlanItemDTO: Codable {
    let exerciseKey: String, exerciseName: String, sets: Int, repsLow: Int, repsHigh: Int, restSeconds: Int
    init(_ t: TemplateExercise) { exerciseKey = t.exerciseKey; exerciseName = t.exerciseName; sets = t.sets; repsLow = t.repsLow; repsHigh = t.repsHigh; restSeconds = t.restSeconds }
}

/// On-device speech-to-text (zh-CN) feeding the chat input.
final class SpeechRecognizer: ObservableObject {
    @Published var transcript = ""
    @Published var isRecording = false
    @Published var error: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func start() {
        error = nil
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                guard status == .authorized else { self?.error = "未授权语音识别，请在系统设置中开启。"; return }
                AVAudioApplication.requestRecordPermission { ok in
                    DispatchQueue.main.async { ok ? self?.begin() : (self?.error = "未授权麦克风。") }
                }
            }
        }
    }

    private func begin() {
        guard let recognizer, recognizer.isAvailable else { error = "当前设备不支持中文语音识别。"; return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            request = req
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in req.append(buffer) }
            engine.prepare()
            try engine.start()
            transcript = ""
            isRecording = true
            task = recognizer.recognitionTask(with: req) { [weak self] result, err in
                DispatchQueue.main.async {
                    if let result { self?.transcript = result.bestTranscription.formattedString }
                    if err != nil || (result?.isFinal ?? false) { self?.stop() }
                }
            }
        } catch {
            self.error = "无法启动录音：\(error.localizedDescription)"
            stop()
        }
    }

    func stop() {
        guard isRecording || engine.isRunning else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
