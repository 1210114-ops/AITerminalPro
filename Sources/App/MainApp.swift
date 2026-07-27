import SwiftUI

@main
struct AITerminalProApp: App {
    @StateObject private var fileSystem = VirtualFileSystem()
    @StateObject private var terminalEngine = TerminalEngine()
    @StateObject private var aiEngine = AIEngine()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(fileSystem)
                .environmentObject(terminalEngine)
                .environmentObject(aiEngine)
        }
    }
}

struct ContentView: View {
    var body: some View {
        TabView {
            TerminalView()
                .tabItem { Label("Terminal", systemImage: "terminal") }

            CodeEditorView()
                .tabItem { Label("Files", systemImage: "doc.text") }

            AIAssistantView()
                .tabItem { Label("AI", systemImage: "sparkles") }
        }
    }
}

private struct AIAssistantView: View {
    @EnvironmentObject private var aiEngine: AIEngine
    @State private var errorLog = ""
    @State private var answer = ""

    var body: some View {
        NavigationStack {
            Form {
                Picker("Provider", selection: $aiEngine.provider) {
                    ForEach(AIProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                apiKeyField
                TextEditor(text: $errorLog)
                    .frame(minHeight: 150)
                Button(aiEngine.isLoading ? "Analyzing…" : "Explain error") {
                    Task { answer = await aiEngine.explainError(errorLog) }
                }
                .disabled(aiEngine.isLoading || errorLog.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if !answer.isEmpty {
                    Section("Analysis") { Text(answer).textSelection(.enabled) }
                }
            }
            .navigationTitle("AI Assistant")
        }
    }

    @ViewBuilder
    private var apiKeyField: some View {
        #if os(iOS)
        SecureField("API key", text: $aiEngine.apiKey)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        #else
        SecureField("API key", text: $aiEngine.apiKey)
        #endif
    }
}
