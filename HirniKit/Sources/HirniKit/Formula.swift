import Foundation

/// Formeln in Datenbanken (Feldtyp «Formel»), wie in Excel, aber mit
/// Feldnamen statt Zellbezügen: `[Preis] * [Menge]`. Eine Formel gilt für die
/// ganze Spalte und rechnet in jeder Zeile mit den Werten dieser Zeile.
///
/// - Rechnen: `+ - * /`, Klammern; Text verbinden mit `&`; vergleichen mit
///   `= <> < > <= >=`. Ein führendes `=` ist erlaubt.
/// - Funktionen (Argumente mit `;` oder `,` getrennt): `SUMME`, `MITTELWERT`,
///   `ANZAHL`, `MIN`, `MAX` – mit einem einzelnen `[Feld]` über die ganze
///   Spalte, sonst über die Argumente; `RUNDEN(x; n)`, `ABS`, `WENN(b; a; c)`,
///   `UND`, `ODER`, `NICHT`, `HEUTE()`, `TAGE(bis; von)`, `JAHR`, `MONAT`,
///   `LÄNGE`, `ISTLEER`. Auch die englischen Namen (`SUM`, `IF` …) gehen.
/// - `WAHR`, `FALSCH`, Texte in `"…"`.
public enum Formula {
    /// Ergebnis einer Formel.
    public enum Value: Equatable, Sendable {
        case number(Double)
        case text(String)
        case bool(Bool)
        case date(Date)
        case error(String)
    }

    /// Fehler beim Lesen einer Formel, mit verständlicher Meldung.
    public struct ParseError: Error, Equatable, LocalizedError {
        public let message: String
        public var errorDescription: String? { message }
    }

    public static let errorText = "#FEHLER"

    // MARK: - Ausrechnen

    /// Rechnet alle Formelfelder aus und setzt die Ergebnisse als Rohwerte in
    /// die Zeilen. Damit funktionieren Anzeige, Filter, Sortierung,
    /// Gruppierung, Berechnungen und Diagramme wie bei anderen Feldern.
    public static func computing(_ database: Database, now: Date = .now) -> Database {
        let formulaFields = database.fields.filter { $0.type == .formula }
        guard !formulaFields.isEmpty else { return database }
        var result = database
        let context = Context(database: database, now: now)
        for index in result.rows.indices {
            for field in formulaFields {
                result.rows[index][field.name] = raw(context.value(of: field, in: database.rows[index], visiting: []))
            }
        }
        return result
    }

    /// Ergebnis eines Formelfelds für eine Zeile.
    public static func value(of field: Field, row: Row, in database: Database, now: Date = .now) -> Value {
        Context(database: database, now: now).value(of: field, in: row, visiting: [])
    }

    /// Ergebnis als Rohwert (wie in einer Zeile nach `computing`).
    public static func rawValue(of field: Field, row: Row, in database: Database, now: Date = .now) -> String {
        raw(value(of: field, row: row, in: database, now: now))
    }

    /// Prüft eine Formel (für den Felder-Editor). `nil` = in Ordnung.
    public static func check(_ formula: String, fields: [Field]) -> String? {
        do {
            var parser = try Parser(formula)
            let node = try parser.parse()
            let known = Set(fields.map { $0.name.lowercased() })
            if let unknown = node.fieldNames.first(where: { !known.contains($0.lowercased()) }) {
                return "Unbekanntes Feld [\(unknown)]"
            }
            return nil
        } catch let error as ParseError {
            return error.message
        } catch {
            return error.localizedDescription
        }
    }

    /// Rohwert für die Zeile.
    static func raw(_ value: Value) -> String {
        switch value {
        case .number(let number): number.isFinite ? CellValue.raw(number: number) : errorText
        case .text(let text): text
        case .bool(let bool): bool ? "Ja" : "Nein"
        case .date(let date): CellValue.raw(date: .init(start: date))
        case .error: errorText
        }
    }

    /// `[Alt]` → `[Neu]` in einer Formel (beim Umbenennen eines Felds).
    public static func renamingField(_ old: String, to new: String, in formula: String) -> String {
        formula.replacingOccurrences(of: "[\(old)]", with: "[\(new)]", options: .caseInsensitive)
    }

    // MARK: - Kontext

    struct Context {
        let database: Database
        let now: Date

        func value(of field: Field, in row: Row, visiting: Set<String>) -> Value {
            guard let formula = field.formula, !formula.trimmingCharacters(in: .whitespaces).isEmpty else { return .text("") }
            guard !visiting.contains(field.name.lowercased()) else { return .error("Formel bezieht sich auf sich selbst") }
            do {
                var parser = try Parser(formula)
                let node = try parser.parse()
                return evaluate(node, row: row, visiting: visiting.union([field.name.lowercased()]))
            } catch {
                return .error((error as? ParseError)?.message ?? "Formel unlesbar")
            }
        }

        func fieldValue(_ name: String, row: Row, visiting: Set<String>) -> Value {
            guard let field = database.fields.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
                return .error("Unbekanntes Feld [\(name)]")
            }
            if field.type == .formula { return value(of: field, in: row, visiting: visiting) }
            let raw = row[field.name].trimmingCharacters(in: .whitespaces)
            switch field.type {
            case .number: return raw.isEmpty ? .text("") : CellValue.number(raw).map(Value.number) ?? .text(raw)
            case .date: return CellValue.date(raw).map { .date($0.start) } ?? .text(raw)
            case .checkbox: return .bool(CellValue.bool(raw))
            default: return .text(raw)
            }
        }

        func evaluate(_ node: Node, row: Row, visiting: Set<String>) -> Value {
            switch node {
            case .number(let number): return .number(number)
            case .text(let text): return .text(text)
            case .bool(let bool): return .bool(bool)
            case .field(let name): return fieldValue(name, row: row, visiting: visiting)
            case .negate(let inner):
                let value = evaluate(inner, row: row, visiting: visiting)
                if case .error = value { return value }
                guard let number = Formula.number(value) else { return .error("Minus braucht eine Zahl") }
                return .number(-number)
            case .binary(let op, let left, let right):
                return binary(op, evaluate(left, row: row, visiting: visiting), evaluate(right, row: row, visiting: visiting))
            case .call(let name, let args):
                return call(name, args, row: row, visiting: visiting)
            }
        }

        func binary(_ op: String, _ a: Value, _ b: Value) -> Value {
            if case .error = a { return a }
            if case .error = b { return b }
            switch op {
            case "&":
                return .text(Formula.text(a) + Formula.text(b))
            case "+", "-":
                // Datum ± Tage, Datum − Datum = Tage
                if case .date(let date) = a {
                    if case .date(let other) = b, op == "-" { return .number(Formula.days(from: other, to: date)) }
                    guard let days = Formula.number(b) else { return .error("Zum Datum lassen sich nur Tage zählen") }
                    return Calendar.current.date(byAdding: .day, value: Int(days.rounded()) * (op == "-" ? -1 : 1), to: date).map(Value.date) ?? .error("Datum")
                }
                guard let x = Formula.number(a), let y = Formula.number(b) else { return .error("\(op) braucht Zahlen") }
                return .number(op == "+" ? x + y : x - y)
            case "*", "/":
                guard let x = Formula.number(a), let y = Formula.number(b) else { return .error("\(op) braucht Zahlen") }
                if op == "/" { return y == 0 ? .error("Division durch 0") : .number(x / y) }
                return .number(x * y)
            default:
                let order = Formula.compare(a, b)
                switch op {
                case "=": return .bool(order == .orderedSame)
                case "<>": return .bool(order != .orderedSame)
                case "<": return .bool(order == .orderedAscending)
                case ">": return .bool(order == .orderedDescending)
                case "<=": return .bool(order != .orderedDescending)
                case ">=": return .bool(order != .orderedAscending)
                default: return .error("Unbekannter Operator \(op)")
                }
            }
        }

        func call(_ rawName: String, _ args: [Node], row: Row, visiting: Set<String>) -> Value {
            let name = Formula.aliases[rawName.uppercased()] ?? rawName.uppercased()
            func arg(_ index: Int) -> Value {
                index < args.count ? evaluate(args[index], row: row, visiting: visiting) : .error("\(rawName): zu wenige Angaben")
            }
            /// Zahlen für SUMME & Co.: ein einzelnes [Feld] = ganze Spalte.
            func numbers() -> [Double]? {
                var values: [Value]
                if args.count == 1, case .field(let field) = args[0] {
                    values = database.rows.map { fieldValue(field, row: $0, visiting: visiting) }
                } else {
                    values = args.map { evaluate($0, row: row, visiting: visiting) }
                }
                if values.contains(where: { if case .error = $0 { true } else { false } }) { return nil }
                values = values.filter { Formula.text($0) != "" }
                return values.compactMap(Formula.number)
            }
            switch name {
            case "SUMME":
                return numbers().map { .number($0.reduce(0, +)) } ?? .error("SUMME")
            case "MITTELWERT":
                guard let values = numbers() else { return .error("MITTELWERT") }
                return values.isEmpty ? .error("MITTELWERT ohne Zahlen") : .number(values.reduce(0, +) / Double(values.count))
            case "ANZAHL":
                if args.count == 1, case .field(let field) = args[0] {
                    return .number(Double(database.rows.filter { Formula.text(fieldValue(field, row: $0, visiting: visiting)) != "" }.count))
                }
                return .number(Double(args.map { evaluate($0, row: row, visiting: visiting) }.filter { Formula.text($0) != "" }.count))
            case "MIN", "MAX":
                guard let values = numbers(), !values.isEmpty else { return .error("\(rawName) ohne Zahlen") }
                return .number(name == "MIN" ? values.min()! : values.max()!)
            case "RUNDEN":
                guard let x = Formula.number(arg(0)) else { return .error("RUNDEN braucht eine Zahl") }
                let digits = args.count > 1 ? Formula.number(arg(1)) ?? 0 : 0
                let factor = pow(10, digits.rounded())
                return .number((x * factor).rounded(.toNearestOrAwayFromZero) / factor)
            case "ABS":
                return Formula.number(arg(0)).map { .number(abs($0)) } ?? .error("ABS braucht eine Zahl")
            case "WENN":
                let condition = arg(0)
                if case .error = condition { return condition }
                return Formula.truthy(condition) ? arg(1) : (args.count > 2 ? arg(2) : .text(""))
            case "UND":
                return .bool(args.indices.allSatisfy { Formula.truthy(arg($0)) })
            case "ODER":
                return .bool(args.indices.contains { Formula.truthy(arg($0)) })
            case "NICHT":
                return .bool(!Formula.truthy(arg(0)))
            case "HEUTE":
                return .date(Calendar.current.startOfDay(for: now))
            case "TAGE":
                guard case .date(let end) = arg(0), case .date(let start) = arg(1) else { return .error("TAGE braucht zwei Daten") }
                return .number(Formula.days(from: start, to: end))
            case "JAHR", "MONAT":
                guard case .date(let date) = arg(0) else { return .error("\(rawName) braucht ein Datum") }
                return .number(Double(Calendar.current.component(name == "JAHR" ? .year : .month, from: date)))
            case "LÄNGE":
                return .number(Double(Formula.text(arg(0)).count))
            case "ISTLEER":
                return .bool(Formula.text(arg(0)).isEmpty)
            default:
                return .error("Unbekannte Funktion \(rawName)")
            }
        }
    }

    static let aliases: [String: String] = [
        "SUM": "SUMME", "AVERAGE": "MITTELWERT", "COUNT": "ANZAHL", "ROUND": "RUNDEN",
        "IF": "WENN", "AND": "UND", "OR": "ODER", "NOT": "NICHT", "TODAY": "HEUTE",
        "DAYS": "TAGE", "YEAR": "JAHR", "MONTH": "MONAT", "LEN": "LÄNGE", "LAENGE": "LÄNGE",
        "ISBLANK": "ISTLEER",
    ]

    // MARK: - Umwandeln

    static func number(_ value: Value) -> Double? {
        switch value {
        case .number(let number): number
        case .bool(let bool): bool ? 1 : 0
        case .text(let text): text.isEmpty ? 0 : CellValue.number(text)
        case .date, .error: nil
        }
    }

    static func text(_ value: Value) -> String {
        switch value {
        case .number(let number): CellValue.display(number: number, format: .plain)
        case .text(let text): text
        case .bool(let bool): bool ? "Ja" : "Nein"
        case .date(let date): CellValue.display(date: .init(start: date))
        case .error: errorText
        }
    }

    static func truthy(_ value: Value) -> Bool {
        switch value {
        case .bool(let bool): bool
        case .number(let number): number != 0
        case .text(let text): !text.isEmpty && text.lowercased() != "nein"
        case .date: true
        case .error: false
        }
    }

    static func compare(_ a: Value, _ b: Value) -> ComparisonResult {
        switch (a, b) {
        case (.date(let x), .date(let y)):
            return x == y ? .orderedSame : (x < y ? .orderedAscending : .orderedDescending)
        default:
            if let x = number(a), let y = number(b), !(isText(a) && isText(b)) {
                return x == y ? .orderedSame : (x < y ? .orderedAscending : .orderedDescending)
            }
            return text(a).localizedCaseInsensitiveCompare(text(b))
        }
    }

    private static func isText(_ value: Value) -> Bool {
        if case .text = value { true } else { false }
    }

    static func days(from start: Date, to end: Date) -> Double {
        let calendar = Calendar.current
        return Double(calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 0)
    }

    // MARK: - Lesen

    indirect enum Node: Equatable {
        case number(Double)
        case text(String)
        case bool(Bool)
        case field(String)
        case negate(Node)
        case binary(String, Node, Node)
        case call(String, [Node])

        var fieldNames: [String] {
            switch self {
            case .field(let name): [name]
            case .negate(let inner): inner.fieldNames
            case .binary(_, let a, let b): a.fieldNames + b.fieldNames
            case .call(_, let args): args.flatMap(\.fieldNames)
            default: []
            }
        }
    }

    enum Token: Equatable {
        case number(Double)
        case text(String)
        case field(String)
        case name(String)
        case op(String)
        case open, close, separator
    }

    struct Parser {
        var tokens: [Token]
        var position = 0

        init(_ formula: String) throws {
            tokens = try Self.tokenize(formula)
        }

        static func tokenize(_ formula: String) throws -> [Token] {
            var text = Substring(formula.trimmingCharacters(in: .whitespacesAndNewlines))
            if text.hasPrefix("=") { text = text.dropFirst() }
            var tokens: [Token] = []
            while let c = text.first {
                if c.isWhitespace { text = text.dropFirst(); continue }
                if c.isNumber || (c == "." && text.dropFirst().first?.isNumber == true) {
                    let digits = text.prefix { $0.isNumber || $0 == "." || $0 == "'" }
                    text = text.dropFirst(digits.count)
                    guard let value = Double(digits.replacingOccurrences(of: "'", with: "")) else {
                        throw ParseError(message: "Zahl «\(digits)» unlesbar")
                    }
                    tokens.append(.number(value))
                } else if c == "\"" {
                    text = text.dropFirst()
                    guard let end = text.firstIndex(of: "\"") else { throw ParseError(message: "Text ohne schliessendes \"") }
                    tokens.append(.text(String(text[..<end])))
                    text = text[text.index(after: end)...]
                } else if c == "[" {
                    text = text.dropFirst()
                    guard let end = text.firstIndex(of: "]") else { throw ParseError(message: "Feld ohne schliessende ]") }
                    tokens.append(.field(text[..<end].trimmingCharacters(in: .whitespaces)))
                    text = text[text.index(after: end)...]
                } else if c.isLetter || c == "_" {
                    let name = text.prefix { $0.isLetter || $0.isNumber || $0 == "_" }
                    text = text.dropFirst(name.count)
                    tokens.append(.name(String(name)))
                } else if c == "(" {
                    tokens.append(.open); text = text.dropFirst()
                } else if c == ")" {
                    tokens.append(.close); text = text.dropFirst()
                } else if c == ";" || c == "," {
                    tokens.append(.separator); text = text.dropFirst()
                } else if let two = ["<=", ">=", "<>"].first(where: { text.hasPrefix($0) }) {
                    tokens.append(.op(two)); text = text.dropFirst(2)
                } else if "+-*/&=<>".contains(c) {
                    tokens.append(.op(String(c))); text = text.dropFirst()
                } else {
                    throw ParseError(message: "Zeichen «\(c)» unbekannt")
                }
            }
            return tokens
        }

        mutating func parse() throws -> Node {
            guard !tokens.isEmpty else { throw ParseError(message: "Formel ist leer") }
            let node = try comparison()
            guard position == tokens.count else { throw ParseError(message: "Unerwartetes Zeichen nach Stelle \(position)") }
            return node
        }

        private var current: Token? { position < tokens.count ? tokens[position] : nil }

        private mutating func take(_ ops: Set<String>) -> String? {
            if case .op(let op) = current, ops.contains(op) { position += 1; return op }
            return nil
        }

        private mutating func comparison() throws -> Node {
            var node = try concat()
            while let op = take(["=", "<>", "<", ">", "<=", ">="]) { node = .binary(op, node, try concat()) }
            return node
        }

        private mutating func concat() throws -> Node {
            var node = try additive()
            while let op = take(["&"]) { node = .binary(op, node, try additive()) }
            return node
        }

        private mutating func additive() throws -> Node {
            var node = try term()
            while let op = take(["+", "-"]) { node = .binary(op, node, try term()) }
            return node
        }

        private mutating func term() throws -> Node {
            var node = try unary()
            while let op = take(["*", "/"]) { node = .binary(op, node, try unary()) }
            return node
        }

        private mutating func unary() throws -> Node {
            if take(["-"]) != nil { return .negate(try unary()) }
            if take(["+"]) != nil { return try unary() }
            return try primary()
        }

        private mutating func primary() throws -> Node {
            guard let token = current else { throw ParseError(message: "Formel endet zu früh") }
            position += 1
            switch token {
            case .number(let value): return .number(value)
            case .text(let value): return .text(value)
            case .field(let name): return .field(name)
            case .open:
                let node = try comparison()
                guard current == .close else { throw ParseError(message: "Es fehlt eine schliessende Klammer") }
                position += 1
                return node
            case .name(let name):
                switch name.uppercased() {
                case "WAHR", "TRUE": return .bool(true)
                case "FALSCH", "FALSE": return .bool(false)
                default: break
                }
                guard current == .open else { throw ParseError(message: "Nach \(name) fehlt «(»") }
                position += 1
                var args: [Node] = []
                if current == .close {
                    position += 1
                    return .call(name, args)
                }
                while true {
                    args.append(try comparison())
                    if current == .separator { position += 1; continue }
                    guard current == .close else { throw ParseError(message: "In \(name)(…) fehlt «)» oder «;»") }
                    position += 1
                    return .call(name, args)
                }
            default:
                throw ParseError(message: "Unerwartetes Zeichen")
            }
        }
    }
}
