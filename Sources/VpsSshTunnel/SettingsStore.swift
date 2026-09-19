import Foundation

struct Settings: Codable, Equatable {
    var server: String = "root@1.1.1.1"
    var localPort: Int = 1080
    var sshPort: Int = 22
    var autoRestart: Bool = true
}

final class SettingsStore {
    private let fileURL: URL

    init() {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/vps-ssh-tunnel", isDirectory: true)
        fileURL = dir.appendingPathComponent(".vps-ssh-tunnel")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    enum LoadResult {
        case loaded(Settings)
        case createdDefault(Settings)
        case corruptedDefault(Settings)
    }

    func load() -> LoadResult {
        guard let data = try? Data(contentsOf: fileURL) else {
            let settings = Settings()
            try? save(settings)
            return .createdDefault(settings)
        }
        guard let settings = try? JSONDecoder().decode(Settings.self, from: data) else {
            let settings = Settings()
            try? save(settings)
            return .corruptedDefault(settings)
        }
        return .loaded(settings)
    }

    func save(_ settings: Settings) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(settings).write(to: fileURL, options: .atomic)
    }
}
