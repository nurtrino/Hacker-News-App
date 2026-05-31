import SwiftUI

struct ContentView: View {
    @State private var action: WebViewAction?
    @State private var canGoBack = false
    @State private var canGoForward = false
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 0) {
            WebView(action: $action,
                    canGoBack: $canGoBack,
                    canGoForward: $canGoForward,
                    isLoading: $isLoading)

            toolbar
        }
        .background(Color.black.ignoresSafeArea())
    }

    private var toolbar: some View {
        HStack(spacing: 28) {
            toolbarButton(systemName: "chevron.backward", enabled: canGoBack) {
                action = .goBack
            }
            toolbarButton(systemName: "chevron.forward", enabled: canGoForward) {
                action = .goForward
            }
            toolbarButton(systemName: "house") {
                action = .home
            }
            toolbarButton(systemName: isLoading ? "xmark" : "arrow.clockwise") {
                action = .reload
            }
        }
        .font(.system(size: 18, weight: .semibold))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private func toolbarButton(systemName: String,
                               enabled: Bool = true,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .frame(width: 44, height: 32)
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .tint(.white)
    }
}

#Preview {
    ContentView()
        .preferredColorScheme(.dark)
}
