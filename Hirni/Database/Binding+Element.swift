import SwiftUI

extension Binding where Value: Identifiable {
    /// Bindung an ein Listenelement über seine Kennung statt über seine Position.
    ///
    /// Wichtig für Listen, aus denen man Einträge löschen kann: Ein Textfeld
    /// schreibt seinen Wert beim Verlieren des Fokus noch einmal zurück, oft
    /// erst nachdem sein Eintrag schon entfernt wurde. Mit `ForEach($liste)`
    /// zeigt die Bindung dann auf eine Position, die es nicht mehr gibt, und
    /// die App stürzt ab («Index out of range»). Hier wird das Schreiben in
    /// diesem Fall einfach ignoriert.
    static func element(_ id: Value.ID, in list: Binding<[Value]>, fallback: Value) -> Binding<Value> {
        Binding(
            get: { list.wrappedValue.first { $0.id == id } ?? fallback },
            set: { newValue in
                guard let index = list.wrappedValue.firstIndex(where: { $0.id == id }) else { return }
                list.wrappedValue[index] = newValue
            }
        )
    }
}
