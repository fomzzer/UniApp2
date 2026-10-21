import PDFKit
import SwiftUI

struct ScheduleDocumentView: View {
    let item: ScheduleItem

    @Environment(ScheduleStore.self) private var store
    @Environment(\.strings) private var s
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var fileURL: URL?
    @State private var failure: Error?

    private var isPinned: Bool {
        store.pinned.map { $0.matches(item) } ?? false
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if !item.isPdf {
                    ContentUnavailableView {
                        Label(s.externalSchedule, systemImage: "safari")
                    } description: {
                        Text(item.url.host() ?? item.url.absoluteString)
                    } actions: {
                        Button(s.openInSafari) { openURL(item.url) }
                            .buttonStyle(.glassProminent)
                            .tint(Theme.accent)
                    }
                } else if let fileURL {
                    PDFKitView(url: fileURL)
                        .ignoresSafeArea(edges: .bottom)
                        .transition(.opacity)
                } else if let failure {
                    ContentUnavailableView {
                        Label(s.documentFailed, systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(s.message(for: failure))
                    } actions: {
                        Button(s.retry) {
                            Task { await load(force: true) }
                        }
                        .buttonStyle(.glassProminent)
                        .tint(Theme.accent)
                        Button(s.openInSafari) { openURL(item.url) }
                            .buttonStyle(.glass)
                    }
                } else {
                    ProgressView(s.loading)
                        .tint(.white)
                        .transition(.opacity)
                }
            }
            .animation(.smooth(duration: 0.35), value: fileURL)
            .animation(.smooth(duration: 0.35), value: failure != nil)
            .navigationTitle(item.major)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(s.close, systemImage: "xmark") { dismiss() }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button(isPinned ? s.unpin : s.pinAsMine, systemImage: isPinned ? "star.fill" : "star") {
                        withAnimation(.smooth(duration: 0.3)) {
                            store.pinned = isPinned ? nil : ScheduleSelection(item: item)
                        }
                    }
                    if let fileURL {
                        ShareLink(item: fileURL)
                    }
                }
            }
            .task { await load(force: false) }
        }
    }

    private func load(force: Bool) async {
        guard item.isPdf else { return }
        failure = nil
        do {
            fileURL = try await store.document(for: item, forceReload: force)
        } catch {
            failure = error
        }
    }
}

struct PDFKitView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .black
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
        }
    }
}
