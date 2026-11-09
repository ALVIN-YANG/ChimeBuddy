import Foundation

enum HookWorkspace {
    /// Optional fallback only. A distributed app never accepts arbitrary Hook
    /// workspaces; source builds keep their own checkout as the default scope.
    static func resolve(bundleURL: URL, environment: [String: String]) -> String? {
        if let configured = environment["CHIMEBUDDY_HOOK_WORKSPACE"] {
            guard configured.hasPrefix("/") else { return nil }
            let path = URL(fileURLWithPath: configured).standardizedFileURL.path
            return path == "/" ? nil : path
        }
        let build = bundleURL.deletingLastPathComponent()
        guard build.lastPathComponent == ".build" else { return nil }
        return build.deletingLastPathComponent().standardizedFileURL.path
    }
}
