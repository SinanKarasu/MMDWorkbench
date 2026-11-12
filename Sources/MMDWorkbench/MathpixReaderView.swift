//
//  MathpixReaderView.swift
//  MMDWorkbench
//
//  A small MMD reading and authoring desk in strict SwiftUI. WebView and WebPage
//  are WebKit's native SwiftUI APIs (macOS/iOS/visionOS 26+), and TextEditor is
//  the dictation surface; there is no AppKit/UIKit representable here.
//

import SwiftUI
import UniformTypeIdentifiers
import WebKit

public struct MathpixReaderView: View {
    @State private var webPage = MathpixWebPage()
    @State private var isChoosingPackage = false
    @State private var isExporting = false
    @State private var isEditorVisible = false
    @State private var isShowingFind = false
    @State private var isConfirmingNewDraft = false
    @State private var isConfirmingOpen = false
    @State private var pendingExternalURL: URL?
    @State private var documentName = "Mathpix Markdown"
    @State private var errorMessage: String?
    @State private var securityScopedSelection: URL?
    @State private var documentURL: URL?
    @State private var documentBaseURL = MathpixWebPage.bundledBaseURL
    @State private var source = Self.demoDocument
    @State private var savedSource = Self.demoDocument

    private let exampleURLs: [URL]

    public init() {
        self.init(exampleURLs: [])
    }

    public init(exampleURLs: [URL]) {
        self.exampleURLs = exampleURLs
    }

    public var body: some View {
        HStack(spacing: 0) {
            if isEditorVisible {
                VStack(spacing: 0) {
                    HStack {
                        Label("MMD Source", systemImage: "text.cursor")
                            .font(.headline)
                        Spacer()
                        if source != savedSource {
                            Text("Edited")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 42)
                    .background(.bar)

                    Divider()

                    TextEditor(text: $source)
                        .font(.body)
                        .textEditorStyle(.plain)
                        .padding(14)
                        .accessibilityLabel("Mathpix Markdown source")
                }
                .frame(minWidth: 360, idealWidth: 480, maxWidth: 640)

                Divider()
            }

            ZStack {
                WebView(webPage.page)
                    .findNavigator(isPresented: $isShowingFind)
                    .scrollBounceBehavior(.basedOnSize, axes: .horizontal)

                if let errorMessage {
                    ContentUnavailableView(
                        "Could Not Render Document",
                        systemImage: "doc.richtext.fill",
                        description: Text(errorMessage)
                    )
                    .padding(40)
                    .background(.regularMaterial, in: .rect(cornerRadius: 18))
                    .padding()
                }
            }
        }
        .navigationTitle(documentName)
        .toolbar {
            ToolbarItemGroup {
                Button("New Dictation Draft", systemImage: "square.and.pencil") {
                    if source == savedSource {
                        newDraft()
                    } else {
                        isConfirmingNewDraft = true
                    }
                }

                Button("Open MMD or Package…", systemImage: "folder") {
                    if source == savedSource {
                        isChoosingPackage = true
                    } else {
                        pendingExternalURL = nil
                        isConfirmingOpen = true
                    }
                }

                if !exampleURLs.isEmpty {
                    Menu("Examples", systemImage: "books.vertical") {
                        ForEach(exampleURLs, id: \.self) { url in
                            Button(url.deletingPathExtension().lastPathComponent) {
                                requestOpen(url)
                            }
                        }
                    }
                }

                Button("Save", systemImage: "square.and.arrow.down") {
                    save()
                }
                .keyboardShortcut("s")

                Button("Save As…", systemImage: "square.and.arrow.down.on.square") {
                    isExporting = true
                }

                Button(
                    isEditorVisible ? "Hide Editor" : "Show Editor",
                    systemImage: isEditorVisible ? "sidebar.left" : "sidebar.left"
                ) {
                    isEditorVisible.toggle()
                }

                Button("Find", systemImage: "magnifyingglass") {
                    isShowingFind.toggle()
                }

                if webPage.page.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .fileExporter(
            isPresented: $isExporting,
            document: MMDFileDocument(text: source),
            contentType: .mathpixMarkdown,
            defaultFilename: documentName
        ) { result in
            switch result {
            case .success(let url):
                adoptExportedDocument(url)
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
        .confirmationDialog(
            "Discard unsaved changes and start a new draft?",
            isPresented: $isConfirmingNewDraft
        ) {
            Button("Discard Changes", role: .destructive) { newDraft() }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Discard unsaved changes and open another document?",
            isPresented: $isConfirmingOpen
        ) {
            Button("Discard Changes", role: .destructive) {
                if let pendingExternalURL {
                    self.pendingExternalURL = nil
                    open(selectionURL: pendingExternalURL)
                } else {
                    isChoosingPackage = true
                }
            }
            Button("Cancel", role: .cancel) {
                pendingExternalURL = nil
            }
        }
        .fileImporter(
            isPresented: $isChoosingPackage,
            allowedContentTypes: [.folder, .mathpixMarkdown],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let selectionURL = urls.first else { return }
                open(selectionURL: selectionURL)
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
        .task(id: PreviewIdentity(source: source, baseURL: documentBaseURL)) {
            // Dictation arrives as ordinary TextEditor changes. A short delay
            // coalesces words and punctuation before rebuilding the preview.
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            await render(source: source, baseURL: documentBaseURL)
        }
        .onOpenURL { requestOpen($0) }
    }

    private func requestOpen(_ url: URL) {
        if source == savedSource {
            open(selectionURL: url)
        } else {
            pendingExternalURL = url
            isConfirmingOpen = true
        }
    }

    /// Opens either a Mathpix export folder or its `.mmd` document. Selecting
    /// the folder provides the strongest sandbox access to `./images/...`;
    /// direct document selection uses the document's parent as the image root.
    private func open(selectionURL: URL) {
        errorMessage = nil

        if let previous = securityScopedSelection {
            previous.stopAccessingSecurityScopedResource()
            securityScopedSelection = nil
        }
        if selectionURL.startAccessingSecurityScopedResource() {
            securityScopedSelection = selectionURL
        }

        do {
            let values = try selectionURL.resourceValues(forKeys: [.isDirectoryKey])
            let isExportFolder = values.isDirectory == true
            let documentURL: URL
            let packageURL: URL

            if isExportFolder {
                packageURL = selectionURL
                let children = try FileManager.default.contentsOfDirectory(
                    at: packageURL,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                )
                let documents = children
                    .filter { $0.pathExtension.lowercased() == "mmd" }
                    .sorted { $0.lastPathComponent < $1.lastPathComponent }

                guard documents.count == 1, let foundDocument = documents.first else {
                    throw ReaderError.expectedOneDocument(found: documents.count)
                }
                documentURL = foundDocument
            } else {
                guard selectionURL.pathExtension.lowercased() == "mmd" else {
                    throw ReaderError.unsupportedSelection
                }
                documentURL = selectionURL
                packageURL = selectionURL.deletingLastPathComponent()
            }

            let source = try String(contentsOf: documentURL, encoding: .utf8)
            // Mathpix commonly gives the `.mmd` a generated identifier, while
            // the enclosing export folder carries the human-readable title.
            documentName = isExportFolder ? packageURL.lastPathComponent : documentURL.lastPathComponent
            // Save exports a writable copy when the source lives in the app bundle.
            self.documentURL = exampleURLs.contains(documentURL) ? nil : documentURL
            documentBaseURL = MathpixWebPage.packageBaseURL
            webPage.resources.setPackageRoot(packageURL)
            self.source = source
            savedSource = source
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func newDraft() {
        releaseSecurityScope()
        documentURL = nil
        documentName = "Book-Dictation-Draft"
        documentBaseURL = MathpixWebPage.bundledBaseURL
        webPage.resources.setPackageRoot(nil)
        source = Self.dictationTemplate
        savedSource = ""
        errorMessage = nil
        isEditorVisible = true
    }

    private func save() {
        guard let documentURL else {
            isExporting = true
            return
        }

        do {
            try source.write(to: documentURL, atomically: true, encoding: .utf8)
            savedSource = source
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func adoptExportedDocument(_ url: URL) {
        releaseSecurityScope()
        if url.startAccessingSecurityScopedResource() {
            securityScopedSelection = url
        }
        documentURL = url
        documentName = url.deletingPathExtension().lastPathComponent
        let packageURL = url.deletingLastPathComponent()
        webPage.resources.setPackageRoot(packageURL)
        documentBaseURL = MathpixWebPage.packageBaseURL
        savedSource = source
        errorMessage = nil
    }

    private func releaseSecurityScope() {
        securityScopedSelection?.stopAccessingSecurityScopedResource()
        securityScopedSelection = nil
    }

    private func render(source: String, baseURL: URL) async {
        do {
            let html = try MathpixHTML.document(source: source)
            errorMessage = nil
            for try await _ in webPage.page.load(html: html, baseURL: baseURL) {}
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    private static let demoDocument = #"""
    \title{Mathpix Markdown in SwiftUI}

    This window is a native SwiftUI \texttt{WebView}. The historical document
    remains Mathpix Markdown; presentation is an adapter around that payload.

    \section*{A small rendering check}

    Inline mathematics: \(E = mc^2\). Display mathematics:

    \[
        y = \frac{\sum_i w_i y_i}{\sum_i w_i}
    \]

    \begin{table}
    \centering
    \begin{tabular}{|l|l|}
    \hline
    Layer & Responsibility \\
    \hline
    MMD & Historical transcription \\
    ATLAS IR & Meaning and execution \\
    SwiftUI & Interaction and presentation \\
    \hline
    \end{tabular}
    \caption{Payloads remain independent of their renderers.}
    \end{table}

    \begin{itemize}
    \item No \texttt{NSViewRepresentable}
    \item No \texttt{UIViewRepresentable}
    \item The Mathpix renderer and document remain local
    \end{itemize}
    """#

    private static let dictationTemplate = #"""
    # Working title

    > Dictation draft. Capture the idea first; organize and verify it later.

    ## The idea

    Begin dictating here.

    ## Why it matters

    ## Historical experience

    ## Connection to TEDL

    ## Connection to ATLAS

    ## Implementation notes

    ```swift
    // Xcode-facing implementation can live beside the explanation.
    ```

    ## Questions to revisit

    - 
    """#
}

/// A document can keep the same text while changing package roots. Include
/// both in SwiftUI's task identity so the preview is rebuilt exactly once for
/// the selected document and old navigations are cancelled with their task.
private struct PreviewIdentity: Hashable {
    let source: String
    let baseURL: URL
}

private struct MMDFileDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.mathpixMarkdown, .plainText]

    var text: String

    init(text: String = "") {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let text = String(data: data, encoding: .utf8) else {
            throw ReaderError.couldNotDecodeDocument
        }
        self.text = text
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard let data = text.data(using: .utf8) else {
            throw ReaderError.couldNotEncodeDocument
        }
        return FileWrapper(regularFileWithContents: data)
    }
}

/// Owns the two objects that must have the same lifetime: the observable page
/// and the local resource handler registered in that page's configuration.
@MainActor
private final class MathpixWebPage {
    static let bundledBaseURL = URL(string: "mmd-resource://bundled/")!
    static let packageBaseURL = URL(string: "mmd-resource://package/")!

    let resources: MathpixPackageSchemeHandler
    let page: WebPage

    init() {
        let resources = MathpixPackageSchemeHandler(
            bundledRoot: Bundle.module.resourceURL!
        )
        var configuration = WebPage.Configuration()
        configuration.urlSchemeHandlers[URLScheme("mmd-resource")!] = resources
        self.resources = resources
        page = WebPage(configuration: configuration)
    }
}

/// Serves only files below the selected Mathpix package directory. A custom
/// scheme is preferable to weakening WebKit's file-URL security policy, and it
/// also works when a sandboxed app receives a security-scoped folder URL.
private final class MathpixPackageSchemeHandler: URLSchemeHandler {
    typealias TaskSequence = AsyncThrowingStream<URLSchemeTaskResult, any Error>

    private let lock = NSLock()
    private let bundledRoot: URL
    private var packageRoot: URL?

    init(bundledRoot: URL) {
        self.bundledRoot = bundledRoot.standardizedFileURL
    }

    func setPackageRoot(_ url: URL?) {
        lock.withLock { packageRoot = url?.standardizedFileURL }
    }

    func reply(for request: URLRequest) -> TaskSequence {
        guard let requestURL = request.url else {
            return failedSequence(PackageResourceError.invalidRequest)
        }
        let root: URL
        switch requestURL.host {
        case "bundled":
            root = bundledRoot
        case "package":
            guard let selectedRoot = lock.withLock({ packageRoot }) else {
                return failedSequence(PackageResourceError.noPackageSelected)
            }
            root = selectedRoot
        default:
            return failedSequence(PackageResourceError.invalidRequest)
        }

        let relativePath = requestURL.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
            .joined(separator: "/")
        let resourceURL = root
            .appending(path: relativePath)
            .standardizedFileURL
        let allowedPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard resourceURL.path.hasPrefix(allowedPrefix) else {
            return failedSequence(PackageResourceError.outsidePackage)
        }

        return AsyncThrowingStream<URLSchemeTaskResult, any Error> { continuation in
            Task {
                do {
                    let data = try await Self.materializedData(at: resourceURL)
                    let mimeType = UTType(filenameExtension: resourceURL.pathExtension)?
                        .preferredMIMEType ?? "application/octet-stream"
                    let response = URLResponse(
                        url: requestURL,
                        mimeType: mimeType,
                        expectedContentLength: data.count,
                        textEncodingName: nil
                    )
                    continuation.yield(URLSchemeTaskResult.response(response))
                    continuation.yield(URLSchemeTaskResult.data(data))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func failedSequence(_ error: any Error) -> TaskSequence {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: error)
        }
    }

    /// File Provider URLs can name files that exist in iCloud but have not yet
    /// been materialized on this device. A coordinated read asks the provider
    /// for the bytes; retrying gives that asynchronous download time to finish.
    private static func materializedData(at url: URL) async throws -> Data {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CocoaError(.fileNoSuchFile)
        }

        do {
            return try coordinatedData(at: url)
        } catch {
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)

            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(30))
            var lastError: any Error = error

            while clock.now < deadline {
                try Task.checkCancellation()
                try await Task.sleep(for: .milliseconds(250))
                do {
                    return try coordinatedData(at: url)
                } catch {
                    lastError = error
                }
            }

            throw lastError
        }
    }

    private static func coordinatedData(at url: URL) throws -> Data {
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var result: Result<Data, any Error>?

        coordinator.coordinate(
            readingItemAt: url,
            options: [],
            error: &coordinationError
        ) { coordinatedURL in
            result = Result { try Data(contentsOf: coordinatedURL) }
        }

        if let result {
            return try result.get()
        }
        if let coordinationError {
            throw coordinationError
        }
        throw CocoaError(.fileReadUnknown)
    }
}

private enum PackageResourceError: Error {
    case invalidRequest
    case noPackageSelected
    case outsidePackage
}

private enum MathpixHTML {
    static func document(source: String) throws -> String {
        let sourceData = try JSONEncoder().encode(source)
        guard var sourceLiteral = String(data: sourceData, encoding: .utf8) else {
            throw ReaderError.couldNotEncodeDocument
        }
        sourceLiteral = sourceLiteral.replacingOccurrences(
            of: "</script",
            with: "<\\/script",
            options: .caseInsensitive
        )

        return #"""
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            :root {
              color-scheme: light dark;
              --canvas: #ecebe7;
              --paper: #ffffff;
              --text: #1d1d1f;
              --secondary-text: #5f5f64;
              --rule: #d1d1d6;
              --code-background: #f2f2f7;
              --link: #075fc5;
              --error-border: #c33;
              --error-text: #900;
            }
            html { background: var(--canvas); }
            body {
              box-sizing: border-box;
              max-width: 1120px;
              min-height: 100vh;
              margin: 0 auto;
              padding: 42px 54px 80px;
              background: var(--paper);
              color: var(--text);
              font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif;
              line-height: 1.48;
            }
            /* Mathpix emits plain paragraphs as unclassed divs. */
            #setText > div:not([class], [id]) + div:not([class], [id]) { margin-top: 0.75em; }
            a { color: var(--link); }
            hr, table, th, td { border-color: var(--rule) !important; }
            pre, code {
              background: var(--code-background);
              color: var(--text);
            }
            blockquote { color: var(--secondary-text); }
            svg { color: currentColor; }
            img { max-width: 100%; height: auto; }
            #render-error {
              display: none;
              padding: 16px;
              border: 1px solid var(--error-border);
              border-radius: 10px;
              color: var(--error-text);
              white-space: pre-wrap;
            }
            @media (prefers-color-scheme: dark) {
              :root {
                --canvas: #111113;
                --paper: #1c1c1e;
                --text: #f2f2f7;
                --secondary-text: #aeaeb2;
                --rule: #48484a;
                --code-background: #2c2c2e;
                --link: #64a8ff;
                --error-border: #ff6961;
                --error-text: #ff9f9a;
              }
            }
            @media (max-width: 700px) {
              body { padding: 24px 22px 60px; }
            }
          </style>
          <script src="mmd-resource://bundled/mathpix-markdown-it.js"></script>
        </head>
        <body>
          <div id="render-error"></div>
          <main id="document"></main>
          <script>
          (() => {
            try {
              const source = \#(sourceLiteral);
              window.loadMathJax(true, true, true);
              document.getElementById("document").innerHTML = window.render(source, {
                htmlTags: false,
                breaks: false,
                padding: 0,
                width: Math.max(document.documentElement.clientWidth - 108, 640)
              });
            } catch (error) {
              const target = document.getElementById("render-error");
              target.style.display = "block";
              const summary = error && error.message
                ? `${error.name || "Error"}: ${error.message}`
                : String(error);
              target.textContent = error && error.stack
                ? `${summary}\n\n${error.stack}`
                : summary;
            }
          })();
          </script>
        </body>
        </html>
        """#
    }
}

private enum ReaderError: LocalizedError {
    case couldNotDecodeDocument
    case couldNotEncodeDocument
    case expectedOneDocument(found: Int)
    case unsupportedSelection

    var errorDescription: String? {
        switch self {
        case .couldNotDecodeDocument:
            "The selected document is not UTF-8 text."
        case .couldNotEncodeDocument:
            "The Mathpix Markdown source could not be encoded for WebKit."
        case .expectedOneDocument(let count):
            "Expected one .mmd document in the selected folder; found \(count)."
        case .unsupportedSelection:
            "Select a Mathpix .mmd document or its export folder."
        }
    }
}

private extension UTType {
    /// Mathpix does not currently publish a system UTI, so use the extension's
    /// dynamic type when available and retain an app-owned exported fallback.
    static let mathpixMarkdown = UTType(filenameExtension: "mmd")
        ?? UTType(
            exportedAs: "com.sinankarasu.mathpix-markdown",
            conformingTo: .plainText
        )
}
