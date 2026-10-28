import HirniKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// Erzeugt aus einer Notiz ein PDF im Format A4: Die Notiz wird als HTML
/// (siehe `NoteHTML`) in einer unsichtbaren Web-Ansicht geladen und von
/// dort auf Seiten verteilt gedruckt.
@MainActor
final class NotePDF: NSObject, WKNavigationDelegate {
    static let a4 = CGSize(width: 595.2, height: 841.8)
    static let margin: CGFloat = 46

    private let webView = WKWebView(frame: CGRect(origin: .zero, size: a4))
    private var loaded: CheckedContinuation<Void, Error>?

    /// PDF einer Notiz als Datei im temporären Ordner («Titel.pdf»).
    static func file(for note: URL, store: VaultStore) async throws -> URL {
        // Ungespeicherte Eingaben zuerst sichern, das PDF liest die Datei.
        await store.openEditor?.flushIfShowing(note)
        let vault = store.vault
        let html = try await Task.detached { try vault.html(ofNote: note) }.value
        let data = try await NotePDF().render(html)
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: FileNaming.sanitized(Vault.title(of: note)) + ".pdf")
        try data.write(to: url)
        return url
    }

    func render(_ html: String) async throws -> Data {
        webView.navigationDelegate = self
        try await withCheckedThrowingContinuation { continuation in
            loaded = continuation
            webView.loadHTMLString(html, baseURL: nil)
        }
        return try await paginate()
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        MainActor.assumeIsolated {
            loaded?.resume()
            loaded = nil
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        MainActor.assumeIsolated {
            loaded?.resume(throwing: error)
            loaded = nil
        }
    }

    #if os(iOS)
    /// iPhone: Druck-Renderer mit dem Druckformat der Web-Ansicht.
    private func paginate() throws -> Data {
        let renderer = UIPrintPageRenderer()
        renderer.addPrintFormatter(webView.viewPrintFormatter(), startingAtPageAt: 0)
        let paper = CGRect(origin: .zero, size: Self.a4)
        renderer.setValue(paper, forKey: "paperRect")
        renderer.setValue(paper.insetBy(dx: Self.margin, dy: Self.margin), forKey: "printableRect")
        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, paper, nil)
        renderer.prepare(forDrawingPages: NSRange(location: 0, length: renderer.numberOfPages))
        for page in 0..<renderer.numberOfPages {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: page, in: UIGraphicsGetPDFContextBounds())
        }
        UIGraphicsEndPDFContext()
        return data as Data
    }
    #else
    /// Mac: Druckauftrag der Web-Ansicht, der in eine Datei speichert.
    ///
    /// WebKit druckt nur aus einem Fenster und nur asynchron (`runModal`);
    /// das synchrone `run()` läuft endlos. Das Fenster bleibt unsichtbar.
    private var printWindow: NSWindow?
    private var printed: CheckedContinuation<Bool, Never>?

    private func paginate() async throws -> Data {
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -10000, y: -10000), size: Self.a4),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = webView
        printWindow = window
        defer { printWindow = nil }
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".pdf")
        let info = NSPrintInfo()
        info.paperSize = Self.a4
        info.topMargin = Self.margin
        info.bottomMargin = Self.margin
        info.leftMargin = Self.margin
        info.rightMargin = Self.margin
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isVerticallyCentered = false
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
        let operation = webView.printOperation(with: info)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        operation.view?.frame = CGRect(origin: .zero, size: Self.a4)
        let success = await withCheckedContinuation { continuation in
            printed = continuation
            operation.runModal(for: window, delegate: self, didRun: #selector(printOperationDidRun(_:success:contextInfo:)), contextInfo: nil)
        }
        guard success else { throw CocoaError(.fileWriteUnknown) }
        defer { try? FileManager.default.removeItem(at: url) }
        return try Data(contentsOf: url)
    }

    @objc private func printOperationDidRun(_ operation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        printed?.resume(returning: success)
        printed = nil
    }
    #endif
}

/// Zum Teilen: Das PDF entsteht erst, wenn es gebraucht wird.
struct NotePDFExport: Transferable {
    let note: URL
    let store: VaultStore

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .pdf) { export in
            SentTransferredFile(try await NotePDF.file(for: export.note, store: export.store))
        }
        .suggestedFileName { Vault.title(of: $0.note) + ".pdf" }
    }
}

/// Zum Teilen der Markdown-Datei, mit den neuesten Eingaben.
struct NoteMarkdownExport: Transferable {
    let note: URL
    let store: VaultStore

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: UTType(filenameExtension: "md") ?? .plainText) { export in
            await export.store.openEditor?.flushIfShowing(export.note)
            let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let copy = folder.appending(path: export.note.lastPathComponent)
            let text = await export.store.read(export.note) ?? ""
            try Data(text.utf8).write(to: copy)
            return SentTransferredFile(copy)
        }
        .suggestedFileName { $0.note.lastPathComponent }
    }
}

/// Für «Als PDF exportieren …» am Mac.
struct PDFFile: FileDocument {
    static let readableContentTypes: [UTType] = [.pdf]
    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
