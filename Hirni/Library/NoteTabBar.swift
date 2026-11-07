import HirniKit
import SwiftUI

#if os(iOS)
import UIKit

/// iPhone: die offenen Notizen als Tabs über dem Editor.
struct NoteTabBar: View {
    @Environment(VaultStore.self) private var store

    var body: some View {
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

    private func tab(_ url: URL) -> some View {
        let isSelected = url == store.selectedNote
        return HStack(spacing: 4) {
            Button {
                // Der Cursor der alten Notiz hätte in der neuen keinen Sinn.
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                store.selectedNote = url
            } label: {
                Text(Vault.title(of: url))
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .frame(maxWidth: 130)
                    .padding(.leading, 12)
                    .padding(.vertical, 6)
            }
            Button("Tab schliessen", systemImage: "xmark") {
                store.closeTab(url)
            }
            .labelStyle(.iconOnly)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(width: 28, height: 28)
            .padding(.trailing, 2)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
        .background(
            isSelected ? AnyShapeStyle(.tint.opacity(0.15)) : AnyShapeStyle(.quaternary.opacity(0.5)),
            in: Capsule()
        )
    }
}
#endif
