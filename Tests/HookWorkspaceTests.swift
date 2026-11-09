import Foundation

@main struct HookWorkspaceTests {
    static func main() {
        assert(HookWorkspace.resolve(bundleURL: URL(fileURLWithPath: "/tmp/example/.build/ChimeBuddy.app"), environment: [:]) == "/tmp/example")
        assert(HookWorkspace.resolve(bundleURL: URL(fileURLWithPath: "/Applications/ChimeBuddy.app"), environment: [:]) == nil)
        assert(HookWorkspace.resolve(bundleURL: URL(fileURLWithPath: "/Applications/ChimeBuddy.app"), environment: ["CHIMEBUDDY_HOOK_WORKSPACE": "/tmp/allowed"]) == "/tmp/allowed")
        for path in ["", ".", "/", "/./", "/not-a-real-workspace/.."] {
            assert(HookWorkspace.resolve(bundleURL: URL(fileURLWithPath: "/Applications/ChimeBuddy.app"), environment: ["CHIMEBUDDY_HOOK_WORKSPACE": path]) == nil)
        }
        print("PASS: portable source Hook scope, installed-app default denial and explicit absolute workspace")
    }
}
