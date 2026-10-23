import PhotosUI
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

/// Die Auswahlfenster für neue Anhänge (Fotos, Kamera, Dateien) und die
/// Vorschau beim Antippen eines Bildes oder PDFs.
struct AttachmentPickers: ViewModifier {
    @Bindable var controller: EditorController
    let importFiles: ([URL]) async -> Void
    let importPhoto: (Data) async -> Void

    #if os(iOS)
    @State private var photoItems: [PhotosPickerItem] = []
    #endif

    func body(content: Content) -> some View {
        content
            .quickLookPreview($controller.previewURL)
            .fileImporter(
                isPresented: isPresented(.files),
                allowedContentTypes: [.image, .pdf],
                allowsMultipleSelection: true
            ) { result in
                if case .success(let urls) = result {
                    Task { await importFiles(urls) }
                }
            }
            #if os(iOS)
            .photosPicker(
                isPresented: isPresented(.photos), selection: $photoItems,
                maxSelectionCount: 10, matching: .images
            )
            .onChange(of: photoItems) { _, items in
                guard !items.isEmpty else { return }
                photoItems = []
                Task {
                    // Der Reihe nach, damit die Bilder in der gewählten Reihenfolge erscheinen.
                    for item in items {
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            await importPhoto(data)
                        }
                    }
                }
            }
            .fullScreenCover(isPresented: isPresented(.camera)) {
                CameraPicker { data in Task { await importPhoto(data) } }
                    .ignoresSafeArea()
            }
            #endif
    }

    private func isPresented(_ source: EditorController.AttachmentSource) -> Binding<Bool> {
        Binding(
            get: { controller.attachmentRequest == source },
            set: { if !$0, controller.attachmentRequest == source { controller.attachmentRequest = nil } }
        )
    }
}
