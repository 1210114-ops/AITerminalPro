import SwiftUI

struct CodeEditorView: View {
    @EnvironmentObject private var fileSystem: VirtualFileSystem
    @State private var folderName = ""
    @State private var result = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Virtual file system") {
                    LabeledContent("Current path", value: fileSystem.currentPath)
                    TextField("New folder", text: $folderName)
                    Button("Create folder") {
                        result = fileSystem.executeCommand("mkdir \"\(folderName)\"")
                        if result.isEmpty { folderName = "" }
                    }
                    if !result.isEmpty { Text(result).foregroundStyle(.red) }
                }
                Section("Contents") {
                    let contents = fileSystem.executeCommand("ls")
                    Text(contents.isEmpty ? "This directory is empty." : contents)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            .navigationTitle("Files")
        }
    }
}
