import Foundation

@main struct CodexProcessEnvironmentTests {
    static func main() {
        let settings: [String: Any] = ["HTTPEnable": 1, "HTTPProxy": "127.0.0.1", "HTTPPort": 7897,
                                      "HTTPSEnable": 1, "HTTPSProxy": "127.0.0.1", "HTTPSPort": 7897,
                                      "ExceptionsList": ["localhost", "127.0.0.1"]]
        let original = ["PATH": "/usr/bin", "CODEX_HOME": "/test/codex"]
        let gui = CodexProcessEnvironment.applying(settings: settings, to: original)
        assert(gui["HTTP_PROXY"] == "http://127.0.0.1:7897" && gui["HTTPS_PROXY"] == "http://127.0.0.1:7897")
        assert(gui["NO_PROXY"] == "localhost,127.0.0.1" && gui["CODEX_HOME"] == original["CODEX_HOME"])
        assert(original["HTTPS_PROXY"] == nil, "Only the child environment changes")
        let explicit = CodexProcessEnvironment.applying(settings: settings, to: ["https_proxy": "http://custom:80", "NO_PROXY": "private.test"])
        assert(explicit["HTTPS_PROXY"] == nil && explicit["https_proxy"] == "http://custom:80" && explicit["NO_PROXY"] == "private.test")
        let optedOut = CodexProcessEnvironment.applying(settings: settings, to: ["HTTPS_PROXY": ""])
        assert(optedOut["HTTPS_PROXY"] == "")
        let all = CodexProcessEnvironment.applying(settings: settings, to: ["ALL_PROXY": "socks5h://custom:1080"])
        assert(all["HTTP_PROXY"] == nil && all["HTTPS_PROXY"] == nil)
        let disabled = CodexProcessEnvironment.applying(settings: ["HTTPSEnable": 0, "HTTPSProxy": "stale", "HTTPSPort": 7897], to: [:])
        assert(disabled["HTTPS_PROXY"] == nil)
        let invalid = CodexProcessEnvironment.applying(settings: ["HTTPSEnable": 1, "HTTPSProxy": "host", "HTTPSPort": 99999], to: [:])
        assert(invalid["HTTPS_PROXY"] == nil)
        print("PASS: GUI system proxy propagation, explicit proxy/opt-out precedence, bypass preservation, disabled and invalid settings")
    }
}
