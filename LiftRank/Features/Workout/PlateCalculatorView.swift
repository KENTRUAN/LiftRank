import SwiftUI

struct PlateCalculatorView: View {
    @State var targetKg: Double
    let unit: WeightUnit
    @Environment(\.dismiss) private var dismiss
    @State private var targetText = ""
    @State private var barText = ""
    @State private var available: Set<Double> = []

    private var plates: [Double] { unit == .kg ? PlateCalculator.defaultPlatesKg : PlateCalculator.defaultPlatesLb }

    var body: some View {
        NavigationStack {
            Form {
                Section("目标") {
                    InputRow("目标重量 (\(unit.label))") {
                        TextField("目标重量", text: $targetText).keyboardType(.decimalPad).formInputStyle()
                    }
                    InputRow("杠铃杆 (\(unit.label))") {
                        TextField("杠铃杆", text: $barText).keyboardType(.decimalPad).formInputStyle()
                    }
                }
                Section("可用杠铃片") {
                    ForEach(plates, id: \.self) { p in
                        let title = "\(p.fmt(2)) \(unit.label)"
                        InputRow(title) {
                            Toggle(title, isOn: Binding(get: { available.contains(p) }, set: { on in if on { available.insert(p) } else { available.remove(p) } }))
                                .labelsHidden()
                        }
                    }
                }
                Section("每侧配重") {
                    let result = PlateCalculator.plates(target: Double(targetText) ?? 0, bar: Double(barText) ?? 0, available: Array(available))
                    if result.perSide.isEmpty {
                        Text("仅空杆").foregroundStyle(.secondary)
                    } else {
                        HStack(spacing: 4) {
                            ForEach(Array(result.perSide.enumerated()), id: \.offset) { _, p in
                                Text(p.fmt(2))
                                    .font(.caption.bold())
                                    .frame(width: 44, height: 28 + CGFloat(p) * (unit == .kg ? 1.6 : 0.7))
                                    .background(Color.accentColor.opacity(0.75), in: RoundedRectangle(cornerRadius: 4))
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        Text("每侧：" + result.perSide.map { $0.fmt(2) }.joined(separator: " + "))
                    }
                    LabeledContent("实际总重", value: "\(result.achieved.fmt(2)) \(unit.label)")
                    let diff = (Double(targetText) ?? 0) - result.achieved
                    if diff > 0.01 { LabeledContent("与目标差", value: "-\(diff.fmt(2)) \(unit.label)").foregroundStyle(.orange) }
                }
            }
            .navigationTitle("杠铃片计算")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .onAppear {
                targetText = unit.fromKg(targetKg).fmt(1)
                barText = unit == .kg ? "20" : "45"
                available = Set(plates)
            }
        }
    }
}
