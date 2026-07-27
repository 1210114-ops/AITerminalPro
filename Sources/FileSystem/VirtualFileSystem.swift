import Foundation
import Combine

@MainActor
public final class VirtualFileSystem: ObservableObject {
    @Published public private(set) var currentPath: String = "/home"
    private let rootURL: URL
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        self.rootURL = documentsURL
            .appendingPathComponent("VirtualRoot", isDirectory: true)
            .standardizedFileURL
        setupInitialDirectories()
    }

    private func setupInitialDirectories() {
        let defaultPaths = ["home", "Documents", "Projects", "Python"]
        for path in defaultPaths {
            try? fileManager.createDirectory(
                at: rootURL.appendingPathComponent(path, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
    }

    public func executeCommand(_ input: String) -> String {
        let components = shellWords(input)
        guard let command = components.first, !command.isEmpty else { return "" }
        let arguments = Array(components.dropFirst())

        switch command {
        case "pwd":
            return currentPath
        case "ls":
            return listDirectory()
        case "cd":
            return changeDirectory(to: arguments.first ?? "/home")
        case "mkdir":
            return createDirectory(name: arguments.first)
        default:
            return "Command not found: \(command)"
        }
    }

    private func listDirectory() -> String {
        let directory = url(forVirtualPath: currentPath)
        do {
            let contents = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            return try contents
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
                .map { url in
                    let values = try url.resourceValues(forKeys: [.isDirectoryKey])
                    return url.lastPathComponent + (values.isDirectory == true ? "/" : "")
                }
                .joined(separator: "  \n")
        } catch {
            return "ls: \(error.localizedDescription)"
        }
    }

    private func changeDirectory(to path: String) -> String {
        guard let destination = resolvedVirtualPath(path) else {
            return "cd: \(path): invalid path"
        }

        let url = url(forVirtualPath: destination)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return "cd: \(path): No such directory"
        }

        currentPath = destination
        return ""
    }

    private func createDirectory(name: String?) -> String {
        guard let name, !name.isEmpty else { return "usage: mkdir <directory>" }
        guard let destination = resolvedVirtualPath(name) else {
            return "mkdir: \(name): invalid path"
        }

        let newURL = url(forVirtualPath: destination)
        do {
            try fileManager.createDirectory(at: newURL, withIntermediateDirectories: true)
            return ""
        } catch {
            return "mkdir: \(name): \(error.localizedDescription)"
        }
    }

    /// Normalizes a shell path without ever resolving above the virtual root.
    private func resolvedVirtualPath(_ path: String) -> String? {
        guard !path.contains("\\") else { return nil }
        var components = path.hasPrefix("/") ? [] : currentPath.split(separator: "/").map(String.init)

        for component in path.split(separator: "/", omittingEmptySubsequences: true).map(String.init) {
            switch component {
            case ".":
                continue
            case "..":
                guard !components.isEmpty else { return nil }
                components.removeLast()
            default:
                guard component != ".", component != "..", !component.contains("\0") else { return nil }
                components.append(component)
            }
        }
        return components.isEmpty ? "/" : "/" + components.joined(separator: "/")
    }

    private func url(forVirtualPath path: String) -> URL {
        let relativePath = String(path.drop(while: { $0 == "/" }))
        return rootURL.appendingPathComponent(relativePath, isDirectory: true).standardizedFileURL
    }

    /// A deliberately small, deterministic shell lexer: whitespace separates words and quotes preserve it.
    private func shellWords(_ input: String) -> [String] {
        var words: [String] = []
        var word = ""
        var quote: Character?
        var escaping = false

        for character in input.trimmingCharacters(in: .whitespacesAndNewlines) {
            if escaping {
                word.append(character)
                escaping = false
            } else if character == "\\" && quote != "'" {
                escaping = true
            } else if character == "\"" || character == "'" {
                if quote == character { quote = nil }
                else if quote == nil { quote = character }
                else { word.append(character) }
            } else if character.isWhitespace && quote == nil {
                if !word.isEmpty { words.append(word); word = "" }
            } else {
                word.append(character)
            }
        }
        if escaping { word.append("\\") }
        if !word.isEmpty { words.append(word) }
        return words
    }
}
