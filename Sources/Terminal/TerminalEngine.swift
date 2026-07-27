import Foundation
import Combine

@MainActor
public final class TerminalEngine: ObservableObject {
    @Published public private(set) var transcript: String
    @Published public var input = ""

    public init() {
        transcript = "\u{001B}[1;32mAI Terminal Pro\u{001B}[0m\nType pwd, ls, cd, or mkdir.\n"
    }

    public func submit(using fileSystem: VirtualFileSystem) {
        let command = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }
        let result = fileSystem.executeCommand(command)
        transcript += "\u{001B}[36m\(fileSystem.currentPath)\u{001B}[0m $ \(command)\n"
        if !result.isEmpty { transcript += result + "\n" }
        input = ""
    }

    public func clear() {
        transcript = ""
    }
}
