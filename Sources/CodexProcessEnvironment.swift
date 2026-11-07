import Foundation
import CFNetwork

/// GUI launches do not inherit shell proxy exports. Codex's HTTP client needs
/// explicit environment values to use the Mac's active system proxy.
enum CodexProcessEnvironment {
    static func current() -> [String: String] {
        let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] ?? [:]
        return applying(settings: settings, to: ProcessInfo.processInfo.environment)
    }

    static func applying(settings: [String: Any], to inherited: [String: String]) -> [String: String] {
        var environment = inherited
        let hasAllProxy = inherited["ALL_PROXY"] != nil || inherited["all_proxy"] != nil
        for (prefix, variable) in [("HTTP", "HTTP_PROXY"), ("HTTPS", "HTTPS_PROXY")] {
            // An explicit environment value (including an empty opt-out) wins.
            guard !hasAllProxy, inherited[variable] == nil, inherited[variable.lowercased()] == nil,
                  (settings[prefix + "Enable"] as? NSNumber)?.boolValue == true,
                  let host = settings[prefix + "Proxy"] as? String, !host.isEmpty,
                  let port = settings[prefix + "Port"] as? NSNumber,
                  (1...65535).contains(port.intValue) else { continue }
            var url = URLComponents()
            url.scheme = "http"; url.host = host; url.port = port.intValue
            if let value = url.url?.absoluteString { environment[variable] = value }
        }
        if inherited["NO_PROXY"] == nil, inherited["no_proxy"] == nil,
           let exceptions = settings["ExceptionsList"] as? [String], !exceptions.isEmpty {
            environment["NO_PROXY"] = exceptions.joined(separator: ",")
        }
        return environment
    }
}
