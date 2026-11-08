import SwiftUI

/// Viewing today's requested plan never starts a workout or opens an editor/chat.
struct TodayTrainingListView: View {
    let plan: DailyPlan

    var body: some View {
        List {
            Section(plan.title) {
                ForEach(plan.items) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(ExerciseNames.display(item.exerciseName)).font(.headline)
                        HStack {
                            Text("\(item.sets) × \(item.repsLow)–\(item.repsHigh)")
                            Spacer()
                            Text("Rest · \(item.restSeconds)s")
                        }.font(.subheadline).foregroundStyle(.secondary)
                    }.padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Today's training")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("todayTrainingList")
    }
}
