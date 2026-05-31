import WebKit

/// Compiles and caches the native `WKContentRuleList` used to block ad and
/// tracking requests at the network layer, plus loads the JS/CSS injected
/// into every YouTube page for cosmetic filtering and ad skipping.
enum ContentBlockerStore {

    /// Identifier under which the compiled rule list is cached by WebKit.
    private static let ruleListIdentifier = "AdFreeTubeBlockerRules"

    /// Compiles the JSON rule list bundled in `Resources/blockerList.json`.
    /// WebKit caches the compiled result, so this is cheap on subsequent runs.
    static func loadRuleList() async -> WKContentRuleList? {
        guard let url = Bundle.main.url(forResource: "blockerList", withExtension: "json"),
              let json = try? String(contentsOf: url, encoding: .utf8) else {
            print("[AdFreeTube] blockerList.json not found in bundle.")
            return nil
        }

        let store = WKContentRuleListStore.default()
        return await withCheckedContinuation { continuation in
            store?.compileContentRuleList(
                forIdentifier: ruleListIdentifier,
                encodedContentRuleList: json
            ) { list, error in
                if let error = error {
                    print("[AdFreeTube] Rule list compile error: \(error)")
                }
                continuation.resume(returning: list)
            }
        }
    }

    /// The JS that skips/hides ads. Injected at document start so it is
    /// active before YouTube's own player scripts run.
    static func injectionScript() -> WKUserScript? {
        loadScript(named: "inject", ext: "js", forMainFrameOnly: true)
    }

    /// CSS is delivered through a tiny JS shim so it can be injected as a
    /// user script (WebKit has no native CSS user-stylesheet API).
    static func cosmeticScript() -> WKUserScript? {
        guard let url = Bundle.main.url(forResource: "cosmetic", withExtension: "css"),
              let css = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        // Escape for safe embedding inside a JS template literal.
        let escaped = css
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
        let source = """
        (function() {
          const style = document.createElement('style');
          style.textContent = `\(escaped)`;
          (document.head || document.documentElement).appendChild(style);
        })();
        """
        return WKUserScript(source: source,
                            injectionTime: .atDocumentEnd,
                            forMainFrameOnly: true)
    }

    private static func loadScript(named name: String,
                                   ext: String,
                                   forMainFrameOnly: Bool) -> WKUserScript? {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            print("[AdFreeTube] Script \(name).\(ext) not found in bundle.")
            return nil
        }
        return WKUserScript(source: source,
                            injectionTime: .atDocumentStart,
                            forMainFrameOnly: forMainFrameOnly)
    }
}
