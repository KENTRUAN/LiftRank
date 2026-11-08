# 段位健身（LiftRank）iOS

## AI avatars and live social gym

[Feature branch documentation](docs/FEATURE_BRANCH.md) describes the implemented app, architecture, verification and remaining prototype work.

[AI provider keys and workout fine-tuning setup](docs/AI_SETUP.md): Tinker powers the specialized workout trainer; generic introductions and avatar generation require a separate Gemini key.

Open the **Community** bottom tab (also linked from **Workout → Enter Gym**). The five tabs are Workout, Ranks, Community, Nutrition and Profile; **Rewards & cosmetics** now lives in Profile. Existing Rewards navigation actions still open it there.

Set up your shared profile once, then enter the preset **Demo Gym** for real multiplayer without location permission. Profile and avatar edits are available in **Profile → Community profile & avatar** or Community settings. Friend requests appear in the room, with **Accept & chat**, a private-message banner and an **Inbox** sheet. The room stays open while you chat or switch tabs; backgrounding or leaving removes your presence.

Entering the live gym starts or resumes the same local workout shown on Home. Tap a bench, rack or platform to log strength sets with weight/reps. Logging fills the next planned set, then adds extra sets as needed. Cardio machines open a separate single-activity timer: **Start cardio** starts timing and **End cardio** saves the exact elapsed duration. Switching from a strength workout with content asks to finish it first; its recorded sets are kept. **Review** opens the appropriate strength or cardio screen. Leaving the room keeps the workout available to resume. The offline sample never starts or records a workout.

Gym data and the floor layout are preset for this prototype. Places search/check-in support remains on the backend but is not exposed in the current UI. Gym image scanning and real floor-plan capture are deferred.

The offline sample works without cloud configuration and labels its simulated members. Real multiplayer uses Firebase and a Cloud Run API; no VM is required. See [backend setup and validation](backend/README.md) for local emulators and the `liftrank-514018` development project. Provider credentials stay server-side. Existing workouts and offline rank cards remain local.

All changes must be made on a new feature branch; never commit or push directly to `main` (see `AGENTS.md`).

SwiftUI + SwiftData，iOS 17+，本地离线版本。按《游戏化力量训练软件｜功能与使用机制》实现第一版。

## 打开与运行

1. 首次使用 Xcode 需要接受许可并切换开发目录（需要管理员密码，只做一次）：

   ```bash
   sudo xcodebuild -license accept
   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
   ```

2. 用 Xcode 打开 `LiftRank.xcodeproj`，选择 `LiftRank` scheme 和 iPhone 模拟器运行。
   工程配置保存在 `project.yml`；改动文件结构后可用 XcodeGen 重新生成工程（`xcodegen generate`），
   并提交更新后的工程与共享 scheme。仓库只保留这一份 Xcode 工程。

3. 命令行构建（需要 macOS 与 Xcode）：

   ```bash
   xcodebuild build -project LiftRank.xcodeproj -scheme LiftRank \
     -destination 'generic/platform=iOS Simulator' \
     -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO
   ```

   产物为 `build/DerivedData/Build/Products/Debug-iphonesimulator/LiftRank.app`。

## 检查与回归测试

不需要安装第三方依赖。仓库 lint 使用 Python 3 标准库，检查空白字符、冲突标记、
JSON/plist/XML、Xcode 源文件成员与测试 scheme；Windows 上使用 `python` 运行同一命令：

```bash
python3 scripts/lint.py
```

macOS 上还可检查 Swift 语法：`python3 scripts/lint.py --swift`。
这不替代编译和运行测试。使用 Xcode 16.4 与 iOS 18.5 模拟器运行 XCTest：

```bash
xcodebuild test -project LiftRank.xcodeproj -scheme LiftRank \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' \
  -parallel-testing-enabled NO -test-timeouts-enabled YES \
  -maximum-test-execution-time-allowance 60 \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO
```

其他 Xcode 版本可按已安装的模拟器调整 `-destination`，或在 Xcode 中按 Command-U。
`LiftRankTests` 覆盖训练生成器的有限动作库与存储加载失败/重试。
GitHub Actions 在 `codex/**` 分支推送及目标为 `main` 的 PR 上运行仓库 lint、Swift 语法检查、
模拟器构建与测试（macOS 15 / Xcode 16.4），并保存测试结果 7 天。
Windows 无法运行 iOS 编译或 XCTest；请等待原生 CI 通过再合并。

## 本轮反馈对应的改动

- **等级系统已删除**，任务页改为「奖励」：每日完成一次力量训练或 10 分钟以上有氧即可领取 Eggs，奖励随段位与连续天数提高；周奖励与赛季里程碑按训练天数计算。
- **商店与外观**：用 Eggs 购买头像框、称号、主题色、段位卡；高段位外观需要达到对应 GSR 段位才能购买与装备。装备后影响头像、称号、全局主题色与分享卡。
- **训练入口统一**：Home 与 Community 都开始或恢复同一份空白训练；第二步可选择预设。只有明确选择预设或请求训练教练安排时才显示清单；不会自动发布每日计划。
- **AI**：所有训练对话与计划使用服务器上的 Tinker 专用模型；已记录组不可修改。身体分析、四周饮食建议、拍照记餐、总结和外观工具使用独立的开发者配置（`Config/AI.xcconfig`，本机密钥文件不入 Git）。通用 AI 不能创建或修改训练计划。社区头像生成与自我介绍另需后端 Gemini Key，见 [AI 配置文档](docs/AI_SETUP.md)。
- **个人与教练形象**：保留 main 的可定制段位小人、个人照片头像和教练名字/外观编辑器；社区健身房仍使用单独确认发布的头像。教练对话支持听写，外观描述在独立编辑器中处理。旧四周方案与旧助手聊天保留；新训练计划进入 Tinker 的统一日程。
- **有氧**：使用单项计时器开始、暂停/继续和结束；结束时保存实际有效时长，不手动填写时间。支持户外小地图、Apple Health、Watch 与锁屏/灵动岛实时活动，详见下文。
- **总结**：训练页右上角或「我的 → 周 / 月 / 季度 / 年总结」，含训练天数、训练量、组数、有氧、段位变化、PR、肌群分布与可选 AI 点评。
- **本地健身社交**：Community 的 Gym / Messages 支持同馆相遇后加好友、聊天和查看共享训练档案。段位卡仍可分享为图片；旧离线卡片只读保留，不能再通过段位码、二维码或账号 ID 添加好友。
- **欢迎页**：体重输入旁可直接切换 kg / lb。

Tinker 已通过服务器的 Anthropic 兼容接口接入训练教练，支持微调检查点推理。模型与密钥由后端配置，不要填入通用 AI 配置。微调脚本、预算限制与验证流程见 [AI 配置文档](docs/AI_SETUP.md)。

## 调试开关（环境变量）

- `LIFTRANK_DEMO=1` 跳过引导并写入 6 次示例训练、体重与饮食记录。
- `LIFTRANK_TAB=0,1,3,4,5` 启动后打开训练、段位、饮食、我的、Community；旧值 2 保留奖励导航兼容。
- `LIFTRANK_ACTIVE=1` 配合 DEMO 自动打开一个进行中的训练。

## 代码结构

- `LiftRank/Models`：SwiftData 模型（用户、动作、训练/动作/组、身体指标、饮食、任务领取、奖励流水、预设）。
- `LiftRank/Engine`：确定性计算。`StrengthScoring`（Epley 1RM、RIR、自重折算、1–1000 评分与九级段位）、
  `RankAggregator`（动作最佳、肌群与总体 GSR）、`Gamification`（连续记录、赛季、XP 等级、任务）、
  `Calculators`（TDEE/营养目标、海军体脂、杠铃片、训练生成器）、`WorkoutPublisher`（发布训练并结算奖励与 PR）。
- `LiftRank/Data`：内置动作库（约 70 个，含力量标准）与演示数据。
- `LiftRank/Features`：训练、段位、Community、饮食/身体、我的 五个标签页；奖励在「我的」中。

## 尚未接入（需要账号、云端或内购）

全球好友动态与排行榜、条码数据库、Strava、Strong/Hevy 导入、Pro 内购（目前为本地模拟开关）、肌肉恢复追踪。Apple Health / Watch / 实时活动与拍照记餐代码已接入；设备权限、真实 Watch 传感器以及通用 AI 接口仍需各自配置和验证。

## Unified training and local gym profiles

All new Home, Siri and Community workout starts create or resume one **blank** SwiftData workout. A separate setup sheet offers an optional preset and the Apple workout type. Start set / End set controls persist the current set, switch presence automatically between Ready, Training and Resting, and open weight/reps confirmation only after the set ends. The gym control remains above the tab bar while scrolling. Public/Anonymous visibility is controlled separately in Community settings. Switching tabs or leaving a room keeps the workout.

Community has **Gym / Messages** sections. Requests and conversations remain accessible inside the room and in Messages afterward. New friend requests require fresh presence and unexpired check-ins for both identities in the same gym; there is no friend-code, QR-code or account-ID adding flow. Previously stored offline rank cards remain read-only. Demo Gym is the clearly labeled development exception to physical proximity; real-gym check-in retains the server location gate.

Lifter profiles use the actual local rank engine. Community settings controls rank sharing, optional workout highlights (recent workout memories, seven-day muscle scores, six-month activity and streak), and up to five public routines. Published workouts refresh opted-in summaries. No body measurements, set weights, actual reps or private notes are uploaded in these summaries. Seven-day body colors represent logged strength scores, not body composition or medical recovery estimates. Public routines contain planned exercise names, sets and reps.

### Apple Health and Apple Watch

The shared workout starts Health tracking after the separate setup step. With the LiftRank Watch companion installed on a paired Watch, the phone requests a live Watch workout, mirrors metrics, and ends/saves it when the local workout finishes. Finishing on Watch stops the same local session; review and publish it on iPhone. Without the companion, iOS 26+ uses a live iPhone HealthKit workout session. iOS 17–25 records timing and manually entered activity into Health when finished; it cannot supply Watch sensor metrics. LiftRank does not remotely start Apple's built-in Workout app.

Build with Xcode 26+ (Swift 6.2+) to enable live iPhone HealthKit sessions. Builds made with Xcode 16.4 use the save-on-finish phone path on all supported iOS versions; Watch tracking remains available.

Install the embedded **LiftRank** app from the Watch app on iPhone, open it once, and allow Health permissions. On iPhone choose **Sync with Apple Health** during workout setup. Strength uses **Traditional strength training**. The separate **Start cardio** flow selects Running, Cycling or another cardio activity and starts its timer and Apple tracking together. A saved workout has a stable Health sync identifier and is excluded from LiftRank's separate Health import to avoid duplicate local records. Sync failures preserve local training and expose Retry Apple Health, including in workout history. The Watch path still needs rehearsal on an actual paired Apple Watch; simulator builds do not validate real sensors or background delivery.

## Community privacy and interactive training

- **Community → settings → Public / Anonymous** controls gym identity. Anonymous members use a generic avatar and cannot receive profile views or make new connections. Sharing recent activity remains a separate choice; existing messages remain in the inbox.
- Blank workouts stay blank. Choose a preset separately, or message **AI trainer** to create, edit or delete remaining todos and daily/weekly schedules. Only requested schedules appear on Home. Saved sets are locked.
- Tap equipment to reserve it. Occupied lifting stations offer **Ask to work in** or **Ask to train together**; the current lifter must accept. Cardio is exclusive. Release a station when finished, or leave the room.
- Start/End set drives orange Training and cyan Resting avatar borders. A saved-set popup appears on the avatar. Community shows a red notification badge for messages and requests.
- Cardio is a single activity with an automatic elapsed timer, no presets or strength exercise controls. **Pause / Resume** excludes breaks from recorded duration. The timer continues while the phone is locked or another app is open; reopening restores the same session. **End cardio** saves active duration without manual entry. Choose **Outdoor** when starting cardio to see a private minimap and local route. Route collection runs while LiftRank is open; no background route recording or route sharing is included.

During cardio, LiftRank shows a Live Activity on the Lock Screen and compatible Dynamic Island. Long-press the island for Pause / Resume and Open. End removes the activity. Live Activities must be enabled in iPhone Settings → LiftRank; their availability does not affect local timing. The elapsed clock needs no continuous background process. Outdoor **route points** are still collected only while LiftRank is open, separately from elapsed time.

See [backend setup and rehearsal](backend/README.md) for cloud configuration and verification commands.
