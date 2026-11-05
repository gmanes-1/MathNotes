import SwiftUI
import PencilKit

// Glue between MathNotes (NotebookDocument, PageRenderer) and the LaTeX sheet.
// Put this file in MathNotes/Services/ next to LatexEngine.swift, DocTemplate.swift and LatexExportView.swift.

extension LatexEngine {
    /// One engine for the whole app, so the 1.2 GB model is loaded once.
    static let shared = LatexEngine()
}

/// Renders a notebook page as dark ink on white: no paper, no imported PDF/photo, no stickers or tape.
/// That is what the model wants (it is told to ignore printed text), and it needs no asset folder.
@MainActor
enum LatexPageSource {
    static func image(document: NotebookDocument, pageIndex: Int) async -> UIImage? {
        guard document.pages.indices.contains(pageIndex) else { return nil }
        let page = document.pages[pageIndex]
        let ink = await document.ink(page.id)
        guard !ink.strokes.isEmpty else { return nil }          // blank page: skip it
        return PageRenderer.image(of: page, ink: ink,
                                  assets: document.package.assetsDirectory,
                                  width: max(page.size.width, 1), scale: 2,
                                  includeBackground: false)
    }
}

extension View {
    /// Adds the "Convert to LaTeX" sheet to the notebook editor.
    func latexExportSheet(isPresented: Binding<Bool>, document: NotebookDocument) -> some View {
        sheet(isPresented: isPresented) {
            LatexExportView(engine: .shared, document: document)
        }
    }
}
