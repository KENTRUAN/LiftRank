import SwiftUI
import Speech
import AVFoundation

/// All workout conversations share the private Tinker trainer and local history.
struct CoachChatView: View {
    let profile: UserProfile
    var body: some View { TrainerConversationView(profile: profile) }
}

/// Chinese speech-to-text feeding the chat input.
final class SpeechRecognizer: ObservableObject {
    @Published var transcript = ""
    @Published var isRecording = false
    @Published var error: String?
    @Published private(set) var needsSettings = false

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var tapInstalled = false

    func start() {
        error = nil
        needsSettings = false
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                guard status == .authorized else {
                    self?.needsSettings = status == .denied
                    self?.error = status == .restricted ? "当前设备限制了语音识别。" : "未授权语音识别。"
                    return
                }
                AVAudioApplication.requestRecordPermission { ok in
                    DispatchQueue.main.async {
                        if ok { self?.begin() }
                        else {
                            self?.needsSettings = true
                            self?.error = "未授权麦克风。"
                        }
                    }
                }
            }
        }
    }

    private func begin() {
        guard let recognizer, recognizer.isAvailable else { error = "当前设备不支持中文语音识别。"; return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement)
            try session.setActive(true)
            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            req.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
            request = req
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                error = "当前没有可用的麦克风输入。"
                stop()
                return
            }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in req.append(buffer) }
            tapInstalled = true
            engine.prepare()
            try engine.start()
            transcript = ""
            isRecording = true
            task = recognizer.recognitionTask(with: req) { [weak self] result, err in
                DispatchQueue.main.async {
                    guard let self, self.request === req else { return }
                    if let result { self.transcript = result.bestTranscription.formattedString }
                    if err != nil && self.transcript.isEmpty { self.error = "没听清楚，请再说一次。" }
                    if err != nil || result?.isFinal == true { self.stop() }
                }
            }
        } catch {
            self.error = "无法启动录音：\(error.localizedDescription)"
            stop()
        }
    }

    func stop() {
        guard request != nil || isRecording || engine.isRunning else { return }
        engine.stop()
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        let activeRequest = request
        request = nil
        activeRequest?.endAudio()
        task?.cancel()
        task = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
