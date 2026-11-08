import ActivityKit
import WidgetKit
import SwiftUI

@main
struct LiftRankLiveActivityBundle: WidgetBundle {
    var body: some Widget { CardioLiveActivity() }
}

struct CardioLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CardioActivityAttributes.self) { context in
            HStack(spacing: 16) {
                Image(systemName: context.state.isPaused ? "pause.circle.fill" : "figure.run").font(.title).foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text("LiftRank · \(context.attributes.activityName)").font(.headline)
                    Text(context.state.isPaused ? "Paused" : context.attributes.outdoor ? "Outdoor cardio" : "Indoor cardio").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    CardioActivityClock(state: context.state).font(.title2.bold()).frame(maxWidth: 120)
                    control(context)
                }
            }.padding(16).activityBackgroundTint(Color(.secondarySystemBackground))
                .widgetURL(url(context))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.activityName, systemImage: "figure.run").font(.headline).foregroundStyle(.orange)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    CardioActivityClock(state: context.state).font(.title2.bold()).frame(width: 110)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.state.isPaused ? "Paused" : "LiftRank · Cardio").foregroundStyle(.secondary)
                        Spacer()
                        control(context)
                        Link("Open", destination: url(context)).font(.callout.bold())
                    }.padding(.top, 8)
                }
            } compactLeading: {
                Image(systemName: context.state.isPaused ? "pause.fill" : "figure.run").foregroundStyle(.orange)
            } compactTrailing: {
                CardioActivityClock(state: context.state).font(.caption2).frame(width: 54)
            } minimal: {
                Image(systemName: context.state.isPaused ? "pause.fill" : "figure.run").foregroundStyle(.orange)
            }
            .widgetURL(url(context)).keylineTint(.orange)
        }
    }
    private func url(_ context: ActivityViewContext<CardioActivityAttributes>) -> URL {
        URL(string: "liftrank://cardio/\(context.attributes.workoutID)")!
    }
    private func control(_ context: ActivityViewContext<CardioActivityAttributes>) -> some View {
        Button(intent: CardioPauseIntent(workoutID: context.attributes.workoutID, paused: !context.state.isPaused)) {
            Label(context.state.isPaused ? "Resume" : "Pause", systemImage: context.state.isPaused ? "play.fill" : "pause.fill")
        }.buttonStyle(.bordered).tint(.orange)
    }
}
