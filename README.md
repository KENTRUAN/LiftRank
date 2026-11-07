# 段位健身（LiftRank）iOS

SwiftUI + SwiftData，iOS 17+，本地离线版本。按《游戏化力量训练软件｜功能与使用机制》实现第一版。

## 打开与运行

1. 首次使用 Xcode 需要接受许可并切换开发目录（需要管理员密码，只做一次）：

   ```bash
   sudo xcodebuild -license accept
   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
   ```

2. 用 Xcode 打开 `LiftRank.xcodeproj`，选择 iPhone 模拟器运行。
   工程由 `project.yml` 通过 xcodegen 生成；改动文件结构后运行 `xcodegen generate`。

3. 不开 Xcode 的命令行构建（当前验证用的方式）：`build/manual/build.sh`，产物为 `build/manual/LiftRank.app`，
   可用 `simctl install` / `simctl launch` 装到模拟器。

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
