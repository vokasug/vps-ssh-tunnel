import Foundation
import AppKit

final class LogStore: ObservableObject {
    @Published private(set) var text = ""

    private let fileURL: URL

    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    init() {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/vps-ssh-tunnel", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("vps-ssh-tunnel.log")
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
    }

    func log(_ message: String) {
        let line = "[\(formatter.string(from: Date()))] \(message)"
        if let data = (line + "\n").data(using: .utf8),
           let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        }
        DispatchQueue.main.async {
            if self.text.isEmpty {
                self.text = line
            } else {
                self.text += "\n" + line
            }
        }
    }

    func copyAll() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
