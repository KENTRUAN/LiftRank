# 段位健身（LiftRank）iOS

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

## 调试开关（环境变量）

- `LIFTRANK_DEMO=1` 跳过引导并写入 6 次示例训练、体重与饮食记录。
- `LIFTRANK_TAB=0..4` 启动后直接打开对应标签页。
- `LIFTRANK_ACTIVE=1` 配合 DEMO 自动打开一个进行中的训练。

## 代码结构

- `LiftRank/Models`：SwiftData 模型（用户、动作、训练/动作/组、身体指标、饮食、任务领取、奖励流水、预设）。
- `LiftRank/Engine`：确定性计算。`StrengthScoring`（Epley 1RM、RIR、自重折算、1–1000 评分与九级段位）、
  `RankAggregator`（动作最佳、肌群与总体 GSR）、`Gamification`（连续记录、赛季、XP 等级、任务）、
  `Calculators`（TDEE/营养目标、海军体脂、杠铃片、训练生成器）、`WorkoutPublisher`（发布训练并结算奖励与 PR）。
- `LiftRank/Data`：内置动作库（约 70 个，含力量标准）与演示数据。
- `LiftRank/Features`：训练、段位、任务、饮食/身体、我的 五个标签页。

## 尚未接入（需要账号、云端或内购）

好友动态与排行榜、AI 拍照记餐、条码数据库、Apple Health、Strava、Strong/Hevy 导入、Apple Watch/小组件/实时活动、
Pro 内购（目前为本地模拟开关）、肌肉恢复追踪。
