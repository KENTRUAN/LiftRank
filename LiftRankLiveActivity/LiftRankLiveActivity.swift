import ActivityKit
import WidgetKit
import SwiftUI

@main
struct LiftRankLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        // WidgetBundleBuilder has no buildEither; erase each availability branch
        // through its public limited-availability wrapper to keep iOS 17 support.
        if #available(iOS 18.0, *) {
            return WidgetBundleBuilder.buildOptional(WidgetBundleBuilder.buildLimitedAvailability(WatchCompatibleWorkoutActivity()))
        } else {
            return WidgetBundleBuilder.buildOptional(WidgetBundleBuilder.buildLimitedAvailability(CardioLiveActivity()))
        }
    }
}

@available(iOS 18.0, *)
private struct WatchCompatibleWorkoutActivity: Widget {
    var body: some WidgetConfiguration { CardioLiveActivity().body.supplementalActivityFamilies([.small, .medium]) }
}

struct CardioLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CardioActivityAttributes.self) { context in
            Group {
                if #available(iOS 18.0, *) { AdaptiveWorkoutActivity(context: context) }
                else { WorkoutActivityContent(context: context, compact: false) }
            }.activityBackgroundTint(Color(.secondarySystemBackground)).widgetURL(context.workoutURL)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.isStrength ? "Strength" : context.attributes.activityName, systemImage: context.attributes.symbol).font(.headline).foregroundStyle(.orange)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    CardioActivityClock(state: context.state).font(.title2.bold()).frame(width: 110)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        WorkoutActivityDetails(context: context)
                        Spacer()
                        WorkoutActivityControl(context: context)
                        Link("Open", destination: context.workoutURL).font(.callout.bold())
                    }.padding(.top, 8)
                }
            } compactLeading: {
                Image(systemName: context.state.isPaused ? "pause.fill" : context.attributes.symbol).foregroundStyle(.orange)
            } compactTrailing: {
                CardioActivityClock(state: context.state).font(.caption2).frame(width: 54)
            } minimal: {
                Image(systemName: context.state.isPaused ? "pause.fill" : context.attributes.symbol).foregroundStyle(.orange)
            }
            .widgetURL(context.workoutURL).keylineTint(.orange)
        }
    }
}

private extension ActivityViewContext where Attributes == CardioActivityAttributes {
    var workoutURL: URL { URL(string: "liftrank://\(attributes.isStrength ? "workout" : "cardio")/\(attributes.workoutID)")! }
}

@available(iOS 18.0, *)
private struct AdaptiveWorkoutActivity: View {
    let context: ActivityViewContext<CardioActivityAttributes>
    @Environment(\.activityFamily) private var family
    var body: some View { WorkoutActivityContent(context: context, compact: family == .small) }
}

private struct WorkoutActivityContent: View {
    let context: ActivityViewContext<CardioActivityAttributes>
    let compact: Bool
    var body: some View {
        HStack(spacing: compact ? 8 : 16) {
            VStack(alignment: .leading, spacing: 4) {
                Label(context.attributes.isStrength ? "Strength" : context.attributes.activityName, systemImage: context.attributes.symbol)
                    .font(compact ? .caption.bold() : .headline).foregroundStyle(.orange)
                WorkoutActivityDetails(context: context)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 8) {
                CardioActivityClock(state: context.state).font(compact ? .headline : .title2.bold()).frame(maxWidth: compact ? 90 : 120)
                if !compact { WorkoutActivityControl(context: context) }
            }
        }.padding(compact ? 8 : 16)
    }
}

private struct WorkoutActivityDetails: View {
    let context: ActivityViewContext<CardioActivityAttributes>
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if context.state.isFinished { Text("Finished") }
            else if context.state.isPaused { Text("Paused") }
            else if context.attributes.isStrength {
                Text("\(context.state.completedSets ?? 0) sets")
                if let rest = context.state.restUntil, rest > Date() {
                    HStack(spacing: 4) {
                        Text("Rest")
                        Text(timerInterval: Date()...rest, countsDown: true).monospacedDigit().frame(maxWidth: 60)
                    }
                }
            } else { Text(context.attributes.outdoor ? "Outdoor cardio" : "Indoor cardio") }
            if !context.isStale, let bpm = context.state.freshHeartRate() {
                Label("\(bpm) bpm", systemImage: "heart.fill").foregroundStyle(.red)
            } else if context.state.watchConnected == true {
                Label("Apple Watch", systemImage: "applewatch")
            }
        }.font(.caption).foregroundStyle(.secondary)
    }
}

private struct WorkoutActivityControl: View {
    let context: ActivityViewContext<CardioActivityAttributes>
    var body: some View {
        if !context.attributes.isStrength && !context.state.isFinished {
            Button(intent: CardioPauseIntent(workoutID: context.attributes.workoutID, paused: !context.state.isPaused)) {
                Label(context.state.isPaused ? "Resume" : "Pause", systemImage: context.state.isPaused ? "play.fill" : "pause.fill")
            }.buttonStyle(.bordered).tint(.orange)
        }
    }
}
