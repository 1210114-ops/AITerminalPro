import SwiftUI

struct TerminalView: View {
    @EnvironmentObject private var fileSystem: VirtualFileSystem
    @EnvironmentObject private var terminalEngine: TerminalEngine
    @State private var useMetalRenderer = true

    var body: some View {
        VStack(spacing: 0) {
            if useMetalRenderer {
                MetalTerminalView(text: terminalEngine.transcript)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding()
            } else {
                ScrollView {
                    Text(AttributedString(terminalEngine.transcript))
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .background(Color.black)
            }

            HStack(spacing: 8) {
                Text("\(fileSystem.currentPath) $")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.green)
                TextField("command", text: $terminalEngine.input)
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.plain)
                    .onSubmit { terminalEngine.submit(using: fileSystem) }
                Button("Run") { terminalEngine.submit(using: fileSystem) }
                Button("Clear") { terminalEngine.clear() }
                Toggle("Metal", isOn: $useMetalRenderer)
                    .labelsHidden()
                    .accessibilityLabel("Use Metal renderer")
            }
            .padding()
            .background(.thinMaterial)
        }
        .navigationTitle("Terminal")
    }
}
