import Foundation

final class OpencodeTelegramManager {
    static let shared = OpencodeTelegramManager()

    private let opencodePath = "/Users/alexander/.opencode/bin/opencode"
    private let botPath = "/opt/homebrew/bin/opencode-telegram"
    private let botLogDir = "Library/Application Support/opencode-telegram-bot/logs"
    private let servePort = 4096
    private let serveKillPattern = "bin/opencode serve"
    private let pathEnv = "/Users/alexander/.opencode/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

    private let queue = DispatchQueue(label: "opencode-telegram.orchestration")
    private var owned: [String: Process] = [:]

    struct Status {
        let serve: Bool
        let bot: Bool
        var running: Bool { serve && bot }
    }

    func probeAsync(completion: @escaping (Status) -> Void) {
        queue.async {
            let status = Status(serve: self.portOpen(self.servePort), bot: self.botRunning())
            DispatchQueue.main.async { completion(status) }
        }
    }

    func start(log: @escaping (String) -> Void, completion: @escaping (Bool) -> Void) {
        queue.async {
            let finish: (Bool) -> Void = { ok in
                DispatchQueue.main.async { completion(ok) }
            }

            if self.portOpen(self.servePort) {
                log("opencode serve уже работает (порт \(self.servePort))")
            } else {
                log("Запуск: opencode serve")
                guard let serve = self.spawnLongRunning(self.opencodePath, ["serve"], name: "serve", log: log) else {
                    finish(false)
                    return
                }
                var up = false
                for _ in 0..<40 {
                    if self.portOpen(self.servePort) { up = true; break }
                    usleep(500_000)
                }
                guard up else {
                    log("ОШИБКА: opencode serve не открыл порт \(self.servePort)")
                    self.terminateProcess(serve, name: "serve", log: log)
                    finish(false)
                    return
                }
                self.owned["serve"] = serve
                log("opencode serve запущен")
            }

            if self.botRunning() {
                log("opencode-telegram уже работает")
            } else {
                let node = self.resolveNodePath()
                let exec = node ?? self.botPath
                let args = node != nil ? [self.botPath] : []
                log("Запуск: \(exec) \(args.joined(separator: " "))")
                let offset = self.botLogOffset()
                guard let bot = self.spawnLongRunning(exec, args, name: "bot", log: log) else {
                    finish(false)
                    return
                }
                var started = false
                for _ in 0..<60 {
                    if !bot.isRunning { break }
                    if self.botLogContains("started!", from: offset) { started = true; break }
                    usleep(500_000)
                }
                guard started else {
                    log("ОШИБКА: opencode-telegram не подтвердил запуск")
                    self.terminateProcess(bot, name: "bot", log: log)
                    finish(false)
                    return
                }
                self.owned["bot"] = bot
                log("opencode-telegram запущен")
            }

            finish(true)
        }
    }

    func stop(log: @escaping (String) -> Void, completion: @escaping () -> Void) {
        queue.async {
            for name in ["bot", "serve"] {
                if let p = self.owned[name] {
                    self.terminateProcess(p, name: name, log: log)
                    self.owned[name] = nil
                }
            }
            if self.botRunning() {
                self.killByPattern(self.botPath, name: "bot", log: log)
            }
            if self.patternAlive(self.serveKillPattern) {
                self.killByPattern(self.serveKillPattern, name: "serve", log: log)
            }
            DispatchQueue.main.async { completion() }
        }
    }

    func shutdownSync() {
        queue.sync {
            for (name, p) in self.owned where p.isRunning {
                self.terminateProcess(p, name: name, log: { _ in })
            }
            self.owned.removeAll()
        }
    }

    private func resolveNodePath() -> String? {
        let fm = FileManager.default
        let candidates = [
            "/opt/homebrew/bin/node",
            "/usr/local/bin/node",
            "/opt/homebrew/opt/node@24/bin/node",
            "/opt/homebrew/opt/node@22/bin/node",
            "/opt/homebrew/opt/node@20/bin/node",
            "/usr/local/opt/node@24/bin/node",
        ]
        return candidates.first { fm.isExecutableFile(atPath: $0) }
    }

    private func runOneShot(_ launchPath: String, _ args: [String], timeout: TimeInterval) -> (Int32, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do {
            try p.run()
        } catch {
            return (-1, error.localizedDescription)
        }
        let watchdog = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        watchdog.cancel()
        p.waitUntilExit()
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    private func portOpen(_ port: Int) -> Bool {
        let (code, _) = runOneShot("/usr/bin/nc", ["-z", "-G", "2", "127.0.0.1", String(port)], timeout: 6)
        return code == 0
    }

    private func botRunning() -> Bool {
        patternAlive(botPath)
    }

    private func patternAlive(_ pattern: String) -> Bool {
        let (code, _) = runOneShot("/usr/bin/pgrep", ["-f", pattern], timeout: 6)
        return code == 0
    }

    private func killByPattern(_ pattern: String, name: String, log: (String) -> Void) {
        _ = runOneShot("/usr/bin/pkill", ["-f", pattern], timeout: 6)
        var waited = 0.0
        while patternAlive(pattern), waited < 3 {
            usleep(200_000)
            waited += 0.2
        }
        if patternAlive(pattern) {
            log("\(name): не отвечает, посылаю SIGKILL")
            _ = runOneShot("/usr/bin/pkill", ["-9", "-f", pattern], timeout: 6)
            usleep(300_000)
        }
        log("\(name): остановлен")
    }

    private func botLogURL() -> URL {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(identifier: "UTC")
        let stamp = df.string(from: Date())
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("\(botLogDir)/bot-\(stamp).log")
    }

    private func botLogOffset() -> Int {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: botLogURL().path),
              let size = attrs[.size] as? Int else { return 0 }
        return size
    }

    private func botLogContains(_ needle: String, from offset: Int) -> Bool {
        let url = botLogURL()
        guard let fh = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? fh.close() }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size > offset else { return false }
        try? fh.seek(toOffset: UInt64(offset))
        let data = fh.readData(ofLength: size - offset)
        return String(data: data, encoding: .utf8)?.contains(needle) ?? false
    }

    private func spawnLongRunning(_ launchPath: String, _ args: [String], name: String,
                                  log: @escaping (String) -> Void) -> Process? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = pathEnv
        p.environment = env
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        var buffer = [UInt8]()
        pipe.fileHandleForReading.readabilityHandler = { fh in
            let data = fh.availableData
            guard !data.isEmpty else {
                fh.readabilityHandler = nil
                var rest = buffer
                if rest.last == 0x0D { rest.removeLast() }
                if !rest.isEmpty {
                    log("  [\(name)] \(String(decoding: rest, as: UTF8.self))")
                }
                return
            }
            buffer += data
            while let nl = buffer.firstIndex(of: 0x0A) {
                var end = nl
                if end > 0, buffer[end - 1] == 0x0D { end -= 1 }
                if end > 0 {
                    log("  [\(name)] \(String(decoding: buffer[0..<end], as: UTF8.self))")
                }
                buffer.removeFirst(nl + 1)
            }
        }
        p.terminationHandler = { [weak self] proc in
            log("\(name): процесс завершён (код \(proc.terminationStatus))")
            self?.queue.async { self?.owned[name] = nil }
        }
        do {
            try p.run()
        } catch {
            log("ОШИБКА: не удалось запустить \(name): \(error.localizedDescription)")
            return nil
        }
        return p
    }

    private func terminateProcess(_ p: Process, name: String, log: (String) -> Void) {
        guard p.isRunning else { return }
        p.interrupt()
        var waited = 0.0
        while p.isRunning, waited < 3 {
            usleep(200_000)
            waited += 0.2
        }
        if p.isRunning {
            p.terminate()
            while p.isRunning, waited < 5 {
                usleep(200_000)
                waited += 0.2
            }
        }
        if p.isRunning {
            log("\(name): не отвечает, посылаю SIGKILL")
            _ = runOneShot("/bin/kill", ["-9", String(p.processIdentifier)], timeout: 5)
            p.waitUntilExit()
        }
        log("\(name): остановлен")
    }
}
