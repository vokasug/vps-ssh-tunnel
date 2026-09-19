import Foundation
import AppKit

enum TunnelManager {

    @discardableResult
    private static func runSync(_ launchPath: String, _ arguments: [String]) -> (Int32, String) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return (-1, error.localizedDescription)
        }
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (process.terminationStatus, output)
    }

    private static func runAsync(_ launchPath: String, _ arguments: [String],
                                 completion: @escaping (Int32, String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = runSync(launchPath, arguments)
            DispatchQueue.main.async { completion(result.0, result.1) }
        }
    }

    static func isTunnelProcessRunning(localPort: Int) -> Bool {
        let (status, _) = runSync("/usr/bin/pgrep", ["-f", "ssh -D \(localPort)"])
        return status == 0
    }

    static func check(localPort: Int, completion: @escaping (Bool, String) -> Void) {
        runAsync("/usr/bin/curl", [
            "--socks5-hostname", "127.0.0.1:\(localPort)",
            "-sS", "-o", "/dev/null", "-w", "%{http_code}",
            "--max-time", "10", "https://api.telegram.org"
        ]) { status, output in
            completion(status == 0 && output == "302", output)
        }
    }

    static func start(settings: Settings, completion: @escaping (Bool, String) -> Void) {
        runAsync("/usr/bin/ssh", [
            "-D", "\(settings.localPort)",
            "-N", "-f",
            "-p", "\(settings.sshPort)",
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=5",
            "-o", "ExitOnForwardFailure=yes",
            "-o", "TCPKeepAlive=no",
            "-o", "ServerAliveInterval=30",
            "-o", "ServerAliveCountMax=3",
            settings.server
        ]) { status, output in
            completion(status == 0, output)
        }
    }

    static func stop(localPort: Int, completion: @escaping () -> Void) {
        runAsync("/usr/bin/pkill", ["-f", "ssh -D \(localPort)"]) { _, _ in
            completion()
        }
    }

    static func stopSync(localPort: Int) {
        _ = runSync("/usr/bin/pkill", ["-f", "ssh -D \(localPort)"])
    }

    static func isAppRunning(bundleId: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == bundleId
        }
    }

    static func isChromeRunning() -> Bool {
        isAppRunning(bundleId: "com.google.Chrome")
    }

    static func quitApp(processName: String, bundleId: String, completion: @escaping () -> Void) {
        runAsync("/usr/bin/pkill", ["-x", processName]) { _, _ in
            DispatchQueue.global(qos: .userInitiated).async {
                var attempts = 0
                while attempts < 50, isAppRunning(bundleId: bundleId) {
                    Thread.sleep(forTimeInterval: 0.1)
                    attempts += 1
                }
                DispatchQueue.main.async { completion() }
            }
        }
    }

    static func quitChrome(completion: @escaping () -> Void) {
        quitApp(processName: "Google Chrome", bundleId: "com.google.Chrome", completion: completion)
    }

    static func openTelegram() {
        runAsync("/usr/bin/open", ["/Applications/Telegram.app"]) { _, _ in }
    }

    static func openChrome(localPort: Int) {
        runAsync("/usr/bin/open", [
            "-a", "Google Chrome",
            "--args", "--proxy-server=socks5://127.0.0.1:\(localPort)"
        ]) { _, _ in }
    }
}
