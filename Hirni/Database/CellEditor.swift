import HirniKit
import SwiftUI

/// Eingabe für einen Zellwert, passend zum Feldtyp. `compact` für
/// Tabellenzellen am Mac, sonst für das Formular.
struct CellEditor: View {
    let field: Field
    @Binding var raw: String
    var compact = false

    var body: some View {
        switch field.type {
        case .text:
            if compact {
                TextField(field.name, text: $raw).textFieldStyle(.plain)
            } else {
                TextField(field.name, text: $raw, axis: .vertical)
            }
        case .url:
            HStack {
                TextField("https://…", text: $raw)
                    .textFieldStyle(.plain)
                    #if os(iOS)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                if let url = URL(string: raw), url.scheme != nil {
                    Link(destination: url) { Image(systemName: "arrow.up.right.square") }
                        .help("Link öffnen")
                }
            }
        case .number:
            NumberCell(field: field, raw: $raw)
        case .checkbox:
            Toggle(field.name, isOn: Binding(
                get: { CellValue.bool(raw) },
                set: { raw = $0 ? CellValue.raw(bool: true) : "" }
            ))
            .labelsHidden()
            #if os(macOS)
            .toggleStyle(.checkbox)
            #endif
        case .select:
            Picker(field.name, selection: $raw) {
                Text("–").tag("")
                ForEach(options, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
        case .multiSelect:
            MultiSelectCell(field: field, options: options, raw: $raw)
        case .date:
            DateCell(field: field, raw: $raw, compact: compact)
        }
    }

    /// Bekannte Optionen, plus ein Wert, der nicht (mehr) in der Liste steht.
    private var options: [String] {
        var list = field.options ?? []
        for value in CellValue.list(raw) where !list.contains(value) && field.type == .multiSelect { list.append(value) }
        if field.type == .select, !raw.isEmpty, !list.contains(raw) { list.append(raw) }
        return list
    }
}

/// Zahl mit Format (CHF, Prozent …). Zeigt den Wert formatiert und speichert
/// ihn als einfache Zahl.
private struct NumberCell: View {
    let field: Field
    @Binding var raw: String

    var body: some View {
        switch field.format ?? .plain {
        case .plain:
            TextField(field.name, value: number, format: .number.locale(locale))
                .modifier(NumberInput())
        case .chf:
            TextField(field.name, value: number, format: .currency(code: "CHF").locale(locale))
                .modifier(NumberInput())
        case .eur:
            TextField(field.name, value: number, format: .currency(code: "EUR").locale(locale))
                .modifier(NumberInput())
        case .usd:
            TextField(field.name, value: number, format: .currency(code: "USD").locale(locale))
                .modifier(NumberInput())
        case .percent:
            TextField(field.name, value: percent, format: .percent.locale(locale))
                .modifier(NumberInput())
        }
    }

    private var locale: Locale { Locale(identifier: "de_CH") }

    private var number: Binding<Double?> {
        Binding(
            get: { CellValue.number(raw) },
            set: { raw = $0.map(CellValue.raw(number:)) ?? "" }
        )
    }

    /// In der Datei steht 12 für 12 %, das Format rechnet mit 0.12.
    private var percent: Binding<Double?> {
        Binding(
            get: { CellValue.number(raw).map { $0 / 100 } },
            set: { raw = $0.map { CellValue.raw(number: $0 * 100) } ?? "" }
        )
    }
}

private struct NumberInput: ViewModifier {
    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .multilineTextAlignment(.trailing)
            #if os(iOS)
            .keyboardType(.decimalPad)
            #endif
    }
}

private struct MultiSelectCell: View {
    let field: Field
    let options: [String]
    @Binding var raw: String

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Toggle(option, isOn: Binding(
                    get: { CellValue.list(raw).contains(option) },
                    set: { isOn in
                        var list = CellValue.list(raw).filter { $0 != option }
                        if isOn { list.append(option) }
                        // Reihenfolge wie in den Optionen, damit die Datei ruhig bleibt.
                        list.sort { (options.firstIndex(of: $0) ?? .max) < (options.firstIndex(of: $1) ?? .max) }
                        raw = CellValue.raw(list: list)
                    }
                ))
            }
            if options.isEmpty {
                Text("Noch keine Optionen – unter «Felder» anlegen")
            }
        } label: {
            Text(raw.isEmpty ? "–" : CellValue.list(raw).joined(separator: ", "))
                .foregroundStyle(raw.isEmpty ? .secondary : .primary)
                .lineLimit(1)
        }
        .menuIndicator(.hidden)
    }
}

private struct DateCell: View {
    let field: Field
    @Binding var raw: String
    let compact: Bool

    var body: some View {
        if let value = CellValue.date(raw) {
            HStack(spacing: 6) {
                DatePicker(field.name, selection: start(value), displayedComponents: components)
                    .labelsHidden()
                if !compact {
                    if let end = value.end {
                        Text("bis")
                        DatePicker("bis", selection: endBinding(value, fallback: end), displayedComponents: components)
                            .labelsHidden()
                        Button("Zeitraum entfernen", systemImage: "minus.circle") {
                            raw = CellValue.raw(date: .init(start: value.start, includesTime: value.includesTime))
                        }
                        .labelStyle(.iconOnly)
                    } else {
                        Button("Zeitraum") {
                            raw = CellValue.raw(date: .init(start: value.start, end: value.start, includesTime: value.includesTime))
                        }
                    }
                }
                Button("Datum entfernen", systemImage: "xmark.circle.fill") { raw = "" }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
            }
        } else if !raw.isEmpty {
            // Unbekanntes Format: zeigen, nicht verändern.
            Text(raw).foregroundStyle(.secondary)
        } else {
            Button("Datum setzen") {
                raw = CellValue.raw(date: .init(start: .now, includesTime: field.includesTime ?? false))
            }
            .buttonStyle(.borderless)
        }
    }

    private var components: DatePickerComponents {
        (field.includesTime ?? false) ? [.date, .hourAndMinute] : [.date]
    }

    private func start(_ value: CellValue.DateValue) -> Binding<Date> {
        Binding(
            get: { value.start },
            set: { raw = CellValue.raw(date: .init(start: $0, end: value.end, includesTime: field.includesTime ?? false)) }
        )
    }

    private func endBinding(_ value: CellValue.DateValue, fallback: Date) -> Binding<Date> {
        Binding(
            get: { value.end ?? fallback },
            set: { raw = CellValue.raw(date: .init(start: value.start, end: $0, includesTime: field.includesTime ?? false)) }
        )
    }
}
