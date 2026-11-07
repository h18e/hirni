import HirniKit
import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Die offenen Notizen als Tabs über dem Editor.
struct NoteTabBar: View {
    @Environment(VaultStore.self) private var store
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    /// Mit ⌘-Klick markierte Tabs, zum gemeinsamen Ablösen.
    @State private var marked: Set<URL> = []
    #endif
    @State private var picksNewTab = false

    var body: some View {
        HStack(spacing: 0) {
            tabs
            if store.addingTab {
                Text("Notiz für neuen Tab wählen")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Button("Abbrechen", systemImage: "xmark") { store.cancelAddingTab() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .frame(width: 32, height: 40)
            } else {
                Button("Notiz in neuem Tab öffnen", systemImage: "plus") {
                    #if os(iOS)
                    hideKeyboard()
                    #endif
                    // Ein eigenes Fenster hat keine Seitenleiste zum Auswählen.
                    if store.isNoteWindow { picksNewTab = true } else { store.beginAddingTab() }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .frame(width: 44, height: 40)
                .contentShape(Rectangle())
                .help("Notiz in neuem Tab öffnen")
            }
        }
        .sheet(isPresented: $picksNewTab) {
            NoteLinkPicker(excluding: store.selectedNote, title: "Notiz in neuem Tab") { target in
                store.openInNewTab(target.url)
            }
        }
    }

    private var tabs: some View {
        ScrollViewReader { scroller in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(store.tabs.urls, id: \.self) { url in
                        tab(url).id(url)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
            .onChange(of: store.selectedNote, initial: true) { _, note in
                if let note { scroller.scrollTo(note) }
            }
        }
    }

    @ViewBuilder
    private func tab(_ url: URL) -> some View {
        let label = tabLabel(url)
        #if os(macOS)
        label
            .overlay {
                if marked.contains(url) {
                    Capsule().strokeBorder(.tint, lineWidth: 1.5)
                }
            }
            .contextMenu {
                let detached = tabsToDetach(with: url)
                Button(detached.count > 1 ? "\(detached.count) Tabs in eigenes Fenster" : "In eigenes Fenster") {
                    detach(detached)
                }
                Button("Tab schliessen") { store.closeTab(url) }
            }
            // Einen Tab aus der Leiste ziehen löst ihn ab.
            .simultaneousGesture(DragGesture(minimumDistance: 30).onEnded { drag in
                if abs(drag.translation.height) > 60 { detach(tabsToDetach(with: url)) }
            })
        #else
        label
        #endif
    }

    private func tabLabel(_ url: URL) -> some View {
        let isSelected = url == store.selectedNote
        return HStack(spacing: 4) {
            Button {
                select(url)
            } label: {
                Text(Vault.title(of: url))
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .frame(maxWidth: 130)
                    .padding(.leading, 12)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
            }
            // Der letzte Tab bleibt: Zurück führt zur Liste.
            if store.tabs.urls.count > 1 {
                Button("Tab schliessen", systemImage: "xmark") {
                    store.closeTab(url)
                }
                .labelStyle(.iconOnly)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .padding(.trailing, 2)
            } else {
                Spacer().frame(width: 12, height: 28)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
        .background(
            isSelected ? AnyShapeStyle(.tint.opacity(0.15)) : AnyShapeStyle(.quaternary.opacity(0.5)),
            in: Capsule()
        )
    }

    private func select(_ url: URL) {
        #if os(macOS)
        if NSEvent.modifierFlags.contains(.command) {
            if marked.remove(url) == nil { marked.insert(url) }
            return
        }
        marked = []
        #else
        hideKeyboard()
        #endif
        store.selectedNote = url
    }

    #if os(iOS)
    /// Der Cursor der alten Notiz hätte in der neuen keinen Sinn.
    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    #endif

    #if os(macOS)
    /// Ein markierter Tab nimmt die übrigen markierten mit.
    private func tabsToDetach(with url: URL) -> [URL] {
        marked.contains(url) ? store.tabs.urls.filter(marked.contains) : [url]
    }

    /// Die Tabs wandern gemeinsam in ein neues Fenster.
    private func detach(_ urls: [URL]) {
        marked = []
        Task {
            for url in urls { await store.openEditor?.flushIfShowing(url) }
            openWindow(id: NoteWindow.id, value: urls)
            for url in urls { store.closeTab(url) }
        }
    }
    #endif
}
