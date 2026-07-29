import SafariServices
import SwiftUI

struct WebLink: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    var readerMode = false
}

/// Where every outbound link in the app funnels through, so the in-app vs
/// Safari preference is honoured from one place.
@MainActor
final class LinkOpener: ObservableObject {
    @Published var presented: WebLink?

    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    func open(_ url: URL) {
        Haptics.tap()
        switch settings.linkTarget {
        case .inApp:
            presented = WebLink(url: url, readerMode: settings.useReaderMode)
        case .safari:
            UIApplication.shared.open(url)
        }
    }

    /// Always uses the in-app browser regardless of preference — used for the
    /// "open in reader" affordance.
    func openInApp(_ url: URL, readerMode: Bool) {
        presented = WebLink(url: url, readerMode: readerMode)
    }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL
    var readerMode = false

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = readerMode
        configuration.barCollapsingEnabled = true

        let controller = SFSafariViewController(url: url, configuration: configuration)
        controller.preferredControlTintColor = UIColor(Color.hnOrange)
        controller.dismissButtonStyle = .close
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

extension View {
    /// Presents whatever the shared `LinkOpener` is currently pointing at.
    func inAppBrowser(_ link: Binding<WebLink?>) -> some View {
        sheet(item: link) { presented in
            SafariView(url: presented.url, readerMode: presented.readerMode)
                .ignoresSafeArea()
        }
    }
}
