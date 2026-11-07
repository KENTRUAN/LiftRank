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

## 本轮反馈对应的改动

- **等级系统已删除**，任务页改为「奖励」：每日完成一次力量训练或 10 分钟以上有氧即可领取 Eggs，奖励随段位与连续天数提高；周奖励与赛季里程碑按训练天数计算。
- **商店与外观**：用 Eggs 购买头像框、称号、主题色、段位卡；高段位外观需要达到对应 GSR 段位才能购买与装备。装备后影响头像、称号、全局主题色与分享卡。
- **设置训练 / 开始训练分离**：训练页「设置训练」编辑计划（动作、组数、次数、休息、排序）；「今日训练」每天自动发布（按已保存计划轮换，没有计划时按「我的」里的目标/天数/器械/经验生成）；开始训练后页面顶部是训练清单（准备项 + 每个动作完成进度）。
- **AI（开发者提供接口）**：用户不再填写 API Key。接口由 `Config/AI.xcconfig` 配置并在构建时写入 Info.plist：把密钥放在 git 忽略的 `Config/AI.local.xcconfig`（参考 `AI.local.example.xcconfig`），协议支持 Claude / OpenAI 兼容（GPT、DeepSeek）/ Gemini；正式发布建议把 `LIFTRANK_AI_BASE_URL` 指向自己的中转服务器、App 里只放应用令牌，避免把服务商密钥打进安装包。调试时也可用 `LIFTRANK_AI_*` 环境变量覆盖。功能：身体综合分析、训练助手对话（自然语言修改今日训练，语音输入，开始训练 / 记录体重 / 记录有氧 / 切换页面）、总结点评。
- **个人形象（小人）**：「段位」页的肌群段位图改为可定制的卡通小人，身体各部位按肌群段位着色（正面 / 背面）。「修改形象」进入形象工坊：肤色、发型、发色、表情、上衣、衣服颜色、配饰、背景共 8 类部件，基础款免费，其余用 Eggs 在商店购买，高级部件需要对应段位。头像、段位卡、好友榜与好友对比都显示小人。
- **AI 助手虚拟形象**：「我的 → AI 助手」或对话页左上角可定义助手的名字和外观：用一句话描述（「粉色长发、戴墨镜、穿黑色连帽衫的女生，叫小粉」）即可生成，离线按关键词解析，AI 开通后由模型理解更自由的描述；也可逐项微调。聊天中直接说「把你的头发改成蓝色」同样会生效。
- **有氧**：训练页顶部切换「有氧」，记录 11 种有氧运动（时长、距离、配速、消耗、心率）；可连接 Apple Health 导入 Apple Watch / Fitness 的运动，手动记录可写回健康 App。需要真机与 HealthKit 权限（entitlements 已配置，签名后生效）。
- **总结**：训练页右上角或「我的 → 周 / 月 / 季度 / 年总结」，含训练天数、训练量、组数、有氧、段位变化、PR、肌群分布与可选 AI 点评。
- **社交（离线）**：「好友与段位卡」生成可分享的段位卡图片与段位码（含二维码），粘贴好友段位码即可加入好友排行榜并对比肌群评分。实时同步与全球榜仍需云端账号。
- **欢迎页**：体重输入旁可直接切换 kg / lb。

关于 Thinking Machines 的 Tinker：它是模型微调 API，不是语音/助手运行时，暂未接入；若以后要训练一个专属教练模型，可用它微调后把兼容接口地址填到 `Config/AI.local.xcconfig`。

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
