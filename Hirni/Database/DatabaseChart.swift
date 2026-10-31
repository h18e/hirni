import Charts
import HirniKit
import SwiftUI

/// Diagramm-Ansicht: Balken oder Linie über ein Feld, Höhe = Anzahl, Summe
/// oder Durchschnitt, optional aufgeteilt nach einem Auswahlfeld.
struct DatabaseChart: View {
    let document: DatabaseDocument

    var body: some View {
        let settings = document.currentView.chart ?? ChartModel.defaultSettings(for: document.database)
        if let data = ChartModel.data(for: settings, rows: document.result.rows, in: document.database), !data.points.isEmpty {
            let valueField = settings.valueField.flatMap(document.database.field(named:))
            VStack(alignment: .leading, spacing: 12) {
                Text(caption(settings))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                chart(data, settings: settings, valueField: valueField)
                    .frame(minHeight: 260)
            }
            .padding(20)
        } else {
            ContentUnavailableView(
                "Nichts darzustellen",
                systemImage: "chart.bar",
                description: Text(emptyReason(settings))
            )
        }
    }

    @ViewBuilder
    private func chart(_ data: ChartData, settings: ChartSettings, valueField: Field?) -> some View {
        let splitField = settings.splitField.flatMap(document.database.field(named:))
        Chart(data.points) { point in
            switch settings.style {
            case .bar:
                BarMark(
                    x: .value("Achse", point.label),
                    y: .value("Wert", point.value)
                )
                .foregroundStyle(by: .value("Teil", point.series ?? "Alle"))
            case .line:
                LineMark(
                    x: .value("Achse", point.label),
                    y: .value("Wert", point.value)
                )
                .foregroundStyle(by: .value("Teil", point.series ?? "Alle"))
                .symbol(by: .value("Teil", point.series ?? "Alle"))
                .interpolationMethod(.monotone)
            }
        }
        .chartXScale(domain: data.labels)
        .chartForegroundStyleScale(domain: data.series.isEmpty ? ["Alle"] : data.series, range: colors(for: data.series, splitField: splitField))
        .chartLegend(data.series.isEmpty ? .hidden : .visible)
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(axisLabel(number, settings: settings, valueField: valueField))
                    }
                }
            }
        }
    }

    /// Farben wie im Kalender: nach der Reihenfolge der Optionen.
    private func colors(for series: [String], splitField: Field?) -> [Color] {
        guard !series.isEmpty else { return [.accentColor] }
        return series.map { name in
            OptionColors.color(splitField?.options?.firstIndex(of: name) ?? (name.hasPrefix("Ohne") ? nil : series.firstIndex(of: name)))
        }
    }

    private func axisLabel(_ number: Double, settings: ChartSettings, valueField: Field?) -> String {
        guard settings.measure != .count, let valueField else {
            return number.formatted(.number.locale(Locale(identifier: "de_CH")))
        }
        return CellValue.display(number: number, format: valueField.format)
    }

    /// «Summe Betrag pro Monat (Datum), aufgeteilt nach Kategorie»
    private func caption(_ settings: ChartSettings) -> String {
        let measure = settings.measure == .count ? "Anzahl Einträge" : "\(settings.measure.label) \(settings.valueField ?? "")"
        var x = settings.xField ?? ""
        if let field = settings.xField.flatMap(document.database.field(named:)), field.type == .date {
            x = "\(settings.interval.label) (\(field.name))"
        }
        var text = "\(measure) pro \(x)"
        if let split = settings.splitField { text += ", aufgeteilt nach \(split)" }
        return text
    }

    private func emptyReason(_ settings: ChartSettings) -> String {
        if settings.xField.flatMap(document.database.field(named:)) == nil {
            return "Unter «Achse» ein Feld für die waagrechte Achse wählen."
        }
        if settings.measure != .count, settings.valueField.flatMap(document.database.field(named:))?.type.isNumeric != true {
            return "Für Summe oder Durchschnitt braucht es ein Zahlenfeld."
        }
        return "Keine passenden Einträge, oder das Achsenfeld ist überall leer."
    }
}

/// Optionen über dem Diagramm: Art, Achse, Wert, Aufteilen.
struct ChartOptions: View {
    let document: DatabaseDocument

    var body: some View {
        let settings = document.currentView.chart ?? ChartModel.defaultSettings(for: document.database)
        let fields = document.database.fields
        let xField = settings.xField.flatMap(document.database.field(named:))

        Picker("Art", selection: binding(\.style, settings)) {
            ForEach(ChartSettings.ChartStyle.allCases, id: \.self) { Label($0.label, systemImage: $0.systemImage).tag($0) }
        }
        .pickerStyle(.segmented)
        .fixedSize()

        Menu {
            Picker("Achse", selection: binding(\.xField, settings)) {
                ForEach(fields.filter { $0.type != .url }) { Text($0.name).tag(String?.some($0.name)) }
            }
            .pickerStyle(.inline)
            if xField?.type == .date {
                Picker("Zeitraster", selection: binding(\.interval, settings)) {
                    ForEach(ChartSettings.DateInterval.allCases, id: \.self) { Text("pro \($0.label)").tag($0) }
                }
                .pickerStyle(.inline)
            }
        } label: {
            Label("Achse: \(xField?.name ?? "–")\(xField?.type == .date ? " (\(settings.interval.label))" : "")", systemImage: "arrow.left.and.right")
        }
        .tint(.secondary)

        Menu {
            Button("Anzahl Einträge") { update(settings) { $0.measure = .count; $0.valueField = nil } }
            ForEach(fields.filter { $0.type.isNumeric }) { field in
                Button("Summe \(field.name)") { update(settings) { $0.measure = .sum; $0.valueField = field.name } }
                Button("Durchschnitt \(field.name)") { update(settings) { $0.measure = .average; $0.valueField = field.name } }
            }
        } label: {
            Label(settings.measure == .count ? "Wert: Anzahl" : "Wert: \(settings.measure.label) \(settings.valueField ?? "")", systemImage: "arrow.up.and.down")
        }
        .tint(.secondary)

        Menu {
            Picker("Aufteilen nach", selection: binding(\.splitField, settings)) {
                Text("Nicht aufteilen").tag(String?.none)
                ForEach(fields.filter { [.select, .multiSelect, .checkbox].contains($0.type) && $0.name != settings.xField }) {
                    Text($0.name).tag(String?.some($0.name))
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label(settings.splitField.map { "Aufgeteilt: \($0)" } ?? "Aufteilen", systemImage: "square.stack.3d.up")
        }
        .tint(settings.splitField != nil ? .accentColor : .secondary)
    }

    private func binding<T>(_ keyPath: WritableKeyPath<ChartSettings, T>, _ settings: ChartSettings) -> Binding<T> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { value in update(settings) { $0[keyPath: keyPath] = value } }
        )
    }

    private func update(_ settings: ChartSettings, _ change: (inout ChartSettings) -> Void) {
        var changed = settings
        change(&changed)
        document.updateView { $0.chart = changed }
    }
}
