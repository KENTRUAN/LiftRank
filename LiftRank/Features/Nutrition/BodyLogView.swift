import SwiftUI
import SwiftData
import Charts

struct BodyLogView: View {
    @Bindable var profile: UserProfile
    @Environment(\.modelContext) private var context
    @Query(sort: \BodyMeasurement.date, order: .reverse) private var measurements: [BodyMeasurement]
    @State private var editing: BodyMetric?

    private func latest(_ m: BodyMetric) -> BodyMeasurement? { measurements.first { $0.metric == m } }

    var body: some View {
        List {
            Section("体重趋势") {
                let weights = measurements.filter { $0.metric == .weight }.sorted { $0.date < $1.date }
                if weights.count >= 2 {
                    Chart(weights) { m in
                        LineMark(x: .value("日期", m.date), y: .value("kg", m.value)).interpolationMethod(.monotone)
                        PointMark(x: .value("日期", m.date), y: .value("kg", m.value))
                    }.frame(height: 150).chartYScale(domain: .automatic(includesZero: false))
                } else {
                    Text("记录两次以上体重后显示趋势。").font(.footnote).foregroundStyle(.secondary)
                }
                NavigationLink { BodyFatCalculatorView(profile: profile) } label: { Label("体脂计算器（美国海军围度法）", systemImage: "percent") }
                Label("Apple Health 同步（读取步数、热量、身体测量；写入训练）尚未接入。", systemImage: "heart.fill").font(.footnote).foregroundStyle(.secondary)
            }
            Section("17 项身体指标") {
                ForEach(BodyMetric.allCases) { m in
                    Button { editing = m } label: {
                        HStack {
                            Text(m.name).foregroundStyle(.primary)
                            Spacer()
                            if let l = latest(m) {
                                Text("\(l.value.fmt(1)) \(m.unit)").monospacedDigit()
                                Text(l.date.shortString).font(.caption2).foregroundStyle(.secondary)
                            } else { Text("—").foregroundStyle(.secondary) }
                        }
                    }
                }
            }
            Section("最近记录") {
                ForEach(measurements.prefix(20)) { m in
                    HStack { Text(m.metric.name); Spacer(); Text("\(m.value.fmt(1)) \(m.metric.unit)"); Text(m.date.shortString).font(.caption).foregroundStyle(.secondary) }
                }
                .onDelete { idx in idx.map { Array(measurements.prefix(20))[$0] }.forEach(context.delete); try? context.save() }
            }
        }
        .sheet(item: $editing) { m in
            MeasurementEditor(metric: m, initial: latest(m)?.value) { value in
                context.insert(BodyMeasurement(date: Date(), metric: m, value: value))
                if m == .weight { profile.bodyweightKg = value }
                if m == .height { profile.heightCm = value }
                try? context.save()
            }
        }
    }
}

struct MeasurementEditor: View {
    let metric: BodyMetric
    let initial: Double?
    let onSave: (Double) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    var body: some View {
        NavigationStack {
            Form {
                HStack { Text(metric.name); Spacer(); TextField("0", text: $text).keyboardType(.decimalPad).multilineTextAlignment(.trailing); Text(metric.unit).foregroundStyle(.secondary) }
            }
            .navigationTitle("记录\(metric.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { if let v = Double(text), v > 0 { onSave(v) }; dismiss() }.disabled(Double(text) == nil) }
            }
            .onAppear { text = initial.map { $0.fmt(1) } ?? "" }
        }
        .presentationDetents([.height(220)])
    }
}

struct BodyFatCalculatorView: View {
    let profile: UserProfile
    @Environment(\.modelContext) private var context
    @State private var sex: Sex = .male
    @State private var height = ""
    @State private var neck = ""
    @State private var waist = ""
    @State private var hip = ""
    @State private var saved = false

    var body: some View {
        let result = BodyFatCalculator.percent(sex: sex, heightCm: Double(height) ?? 0, neckCm: Double(neck) ?? 0, waistCm: Double(waist) ?? 0, hipCm: Double(hip) ?? 0)
        Form {
            Section("围度 (cm)") {
                Picker("性别", selection: $sex) { ForEach(Sex.allCases) { Text($0.label).tag($0) } }.pickerStyle(.segmented)
                field("身高", $height); field("颈围", $neck); field("腰围（肚脐处）", $waist)
                if sex == .female { field("臀围", $hip) }
            }
            Section("结果") {
                if let r = result {
                    HStack { Text("估算体脂率"); Spacer(); Text("\(r.fmt(1)) %").font(.title2.bold()) }
                    Button(saved ? "已保存到身体数据" : "保存为今日体脂记录") {
                        context.insert(BodyMeasurement(date: Date(), metric: .bodyFat, value: r))
                        try? context.save(); saved = true
                    }.disabled(saved)
                } else { Text("请填写完整围度；腰围需大于颈围。").foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("体脂计算器")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { sex = profile.sex; height = profile.heightCm.fmt(0) }
    }
    private func field(_ l: String, _ b: Binding<String>) -> some View {
        HStack { Text(l); Spacer(); TextField("0", text: b).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
    }
}
