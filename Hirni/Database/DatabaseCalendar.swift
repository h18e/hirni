import HirniKit
import SwiftUI

/// Kalender-Ansicht: Einträge auf einem Monatskalender nach einem Datumsfeld,
/// farbig nach einem Auswahlfeld. Wochenenden sind hinterlegt.
struct DatabaseCalendar: View {
    let document: DatabaseDocument
    /// Eintrag öffnen (Formular).
    let open: (String) -> Void

    @State private var month = Date.now
    @State private var selectedDay: SelectedDay?

    private let calendar = CalendarModel.calendar

    var body: some View {
        let view = document.currentView
        if let dateField = CalendarModel.dateField(for: view, in: document.database) {
            let colorField = view.colorField.flatMap(document.database.field(named:))
            let weeks = CalendarModel.weeks(ofMonthContaining: month)
            let entries = CalendarModel.entries(
                document.result.rows, dateField: dateField,
                from: weeks.first?.first ?? month, to: weeks.last?.last ?? month
            )
            VStack(spacing: 0) {
                header
                weekdayHeader
                Grid(horizontalSpacing: 1, verticalSpacing: 1) {
                    ForEach(weeks, id: \.first) { week in
                        GridRow {
                            ForEach(week, id: \.self) { day in
                                DayCell(
                                    day: day,
                                    isInMonth: calendar.isDate(day, equalTo: month, toGranularity: .month),
                                    entries: entries[day] ?? [],
                                    titleField: document.database.fields.first,
                                    colorField: colorField
                                )
                                .onTapGesture { selectedDay = SelectedDay(date: day) }
                            }
                        }
                    }
                }
                .background(Color.secondary.opacity(0.25))
                if let colorField { Legend(field: colorField) }
            }
            .sheet(item: $selectedDay) { day in
                DaySheet(document: document, day: day.date, dateField: dateField, colorField: colorField, open: open)
            }
        } else {
            ContentUnavailableView(
                "Kein Datumsfeld",
                systemImage: "calendar.badge.exclamationmark",
                description: Text("Für den Kalender braucht die Datenbank ein Feld vom Typ «Datum». Unter «Felder» lässt es sich anlegen.")
            )
        }
    }

    private var header: some View {
        HStack {
            Text(month.formatted(.dateTime.locale(Locale(identifier: "de_CH")).month(.wide).year()))
                .font(.title3.bold())
            Spacer()
            Button("Vorheriger Monat", systemImage: "chevron.left") { shift(-1) }
                .keyboardShortcut(.leftArrow, modifiers: .command)
            Button("Heute") { month = .now }
            Button("Nächster Monat", systemImage: "chevron.right") { shift(1) }
                .keyboardShortcut(.rightArrow, modifiers: .command)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var weekdayHeader: some View {
        HStack(spacing: 1) {
            ForEach(Array(["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"].enumerated()), id: \.offset) { index, name in
                Text(name)
                    .font(.caption.bold())
                    .foregroundStyle(index >= 5 ? Color.accentColor : .secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.bottom, 4)
    }

    private func shift(_ months: Int) {
        month = calendar.date(byAdding: .month, value: months, to: month) ?? month
    }
}

private struct SelectedDay: Identifiable {
    let date: Date
    var id: Date { date }
}

/// Feste Farben für Auswahl-Optionen, in der Reihenfolge der Optionen.
enum OptionColors {
    static let palette: [Color] = [.blue, .orange, .green, .purple, .pink, .teal, .red, .yellow, .indigo, .brown, .mint, .cyan]

    static func color(_ index: Int?) -> Color {
        guard let index else { return .gray }
        return palette[index % palette.count]
    }
}

private struct DayCell: View {
    let day: Date
    let isInMonth: Bool
    let entries: [Row]
    let titleField: Field?
    let colorField: Field?

    private var maxVisible: Int {
        #if os(iOS)
        2
        #else
        4
        #endif
    }

    var body: some View {
        let isToday = CalendarModel.calendar.isDateInToday(day)
        VStack(alignment: .leading, spacing: 2) {
            Text(day.formatted(.dateTime.day()))
                .font(.caption.weight(isToday ? .bold : .regular))
                .foregroundStyle(isToday ? .white : (isInMonth ? .primary : .secondary))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(isToday ? Color.accentColor : .clear, in: Capsule())
            ForEach(entries.prefix(maxVisible)) { row in
                let color = OptionColors.color(CalendarModel.colorIndex(of: row, colorField: colorField))
                Text(title(of: row))
                    .font(.caption2)
                    .lineLimit(1)
                    .padding(.horizontal, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(color.opacity(0.25), in: RoundedRectangle(cornerRadius: 3))
                    .overlay(alignment: .leading) {
                        Rectangle().fill(color).frame(width: 2)
                    }
            }
            if entries.count > maxVisible {
                Text("+\(entries.count - maxVisible)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(3)
        .frame(maxWidth: .infinity, minHeight: cellHeight, maxHeight: .infinity, alignment: .topLeading)
        .background(background)
        .contentShape(Rectangle())
        .opacity(isInMonth ? 1 : 0.55)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(day.formatted(date: .complete, time: .omitted)), \(entries.count) Einträge")
    }

    private var cellHeight: CGFloat {
        #if os(iOS)
        64
        #else
        96
        #endif
    }

    private var background: Color {
        #if os(iOS)
        let base = Color(uiColor: .systemBackground)
        #else
        let base = Color(nsColor: .textBackgroundColor)
        #endif
        return CalendarModel.isWeekend(day) ? base.mix(with: .accentColor, by: 0.06) : base
    }

    private func title(of row: Row) -> String {
        guard let titleField else { return "Eintrag" }
        let text = CellValue.display(row[titleField.name], for: titleField)
        return text.isEmpty ? "Ohne Namen" : text
    }
}

/// Farbschlüssel unter dem Kalender.
private struct Legend: View {
    let field: Field

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array((field.options ?? []).enumerated()), id: \.offset) { index, option in
                    Label {
                        Text(option).font(.caption)
                    } icon: {
                        Circle().fill(OptionColors.color(index)).frame(width: 8, height: 8)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}

/// Einträge eines Tages, mit «Neuer Eintrag an diesem Tag».
private struct DaySheet: View {
    let document: DatabaseDocument
    let day: Date
    let dateField: Field
    let colorField: Field?
    let open: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                let entries = CalendarModel.entries(document.result.rows, dateField: dateField, from: day, to: day)[day] ?? []
                ForEach(entries) { row in
                    Button {
                        dismiss()
                        open(row.id)
                    } label: {
                        HStack {
                            Circle()
                                .fill(OptionColors.color(CalendarModel.colorIndex(of: row, colorField: colorField)))
                                .frame(width: 10, height: 10)
                            VStack(alignment: .leading) {
                                let title = document.database.fields.first.map { CellValue.display(row[$0.name], for: $0) } ?? ""
                                Text(title.isEmpty ? "Ohne Namen" : title)
                                if let colorField, !row[colorField.name].isEmpty {
                                    Text(row[colorField.name]).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .tint(.primary)
                }
                if entries.isEmpty {
                    Text("Keine Einträge an diesem Tag").foregroundStyle(.secondary)
                }
                Section {
                    Button("Neuer Eintrag an diesem Tag", systemImage: "plus") {
                        let date = CellValue.raw(date: .init(start: day, includesTime: dateField.includesTime ?? false))
                        let id = document.addRow(values: [dateField.name: date])
                        dismiss()
                        open(id)
                    }
                }
            }
            .navigationTitle(day.formatted(.dateTime.locale(Locale(identifier: "de_CH")).weekday(.wide).day().month(.wide)))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
            }
        }
        #if os(macOS)
        .frame(minWidth: 360, minHeight: 320)
        #endif
    }
}
