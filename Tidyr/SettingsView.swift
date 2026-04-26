import SwiftUI

struct SettingsView: View {
    @State private var apiKey: String = KeychainHelper.load() ?? ""
    @State private var status: ConnectionStatus = .idle
    @State private var showKey = false
    @State private var clipboardKey: String?
    @Environment(\.dismiss) private var dismiss

    enum ConnectionStatus {
        case idle
        case testing
        case success(String)
        case failure(String)

        var isTesting: Bool {
            if case .testing = self { return true }
            return false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            VStack(alignment: .leading, spacing: 6) {
                Text("AI Settings")
                    .font(.title2).fontWeight(.bold)
                Text("Tidyr uses Google Gemini to analyze your files. Your key is stored securely in this Mac's Keychain and is never sent anywhere except Google.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)

            Divider()

            if let detected = clipboardKey {
                HStack(spacing: 10) {
                    Image(systemName: "doc.on.clipboard")
                        .foregroundStyle(.blue)
                    Text("API key detected in clipboard")
                        .font(.callout)
                    Spacer()
                    Button("Use It") {
                        apiKey = detected
                        clipboardKey = nil
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    Button {
                        clipboardKey = nil
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.blue.opacity(0.08))

                Divider()
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Gemini API Key").fontWeight(.medium)

                HStack {
                    Group {
                        if showKey {
                            TextField("Paste your API key here", text: $apiKey)
                        } else {
                            SecureField("Paste your API key here", text: $apiKey)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))

                    Button {
                        showKey.toggle()
                    } label: {
                        Image(systemName: showKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                    .help(showKey ? "Hide key" : "Show key")
                }

                Button("Get a free API key at Google AI Studio →") {
                    NSWorkspace.shared.open(URL(string: "https://aistudio.google.com/app/apikey")!)
                }
                .buttonStyle(.link)
                .font(.callout)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)

            Divider()

            switch status {
            case .idle:
                EmptyView()
            case .testing:
                HStack(spacing: 10) {
                    ProgressView().scaleEffect(0.7)
                    Text("Connecting to Gemini…")
                        .foregroundStyle(.secondary).font(.callout)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                Divider()
            case .success(let msg):
                Label(msg, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green).font(.callout)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                Divider()
            case .failure(let err):
                Label(err, systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red).font(.callout)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                Divider()
            }

            HStack {
                if KeychainHelper.hasKey {
                    Button("Remove Key", role: .destructive) {
                        KeychainHelper.delete()
                        apiKey = ""
                        status = .idle
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save & Verify") { saveAndVerify() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(trimmedKey.isEmpty || status.isTesting)
            }
            .padding(24)
        }
        .frame(width: 480)
        .onAppear { checkClipboard() }
    }

    private var trimmedKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func checkClipboard() {
        guard let pasted = NSPasteboard.general.string(forType: .string) else { return }
        let trimmed = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("AIza"), trimmed.count > 20, trimmed.count < 60 else { return }
        guard trimmed != (KeychainHelper.load() ?? ""), trimmed != trimmedKey else { return }
        clipboardKey = trimmed
    }

    private func saveAndVerify() {
        status = .testing
        let key = trimmedKey
        Task {
            do {
                let reply = try await GeminiService.testConnection(apiKey: key)
                let preview = reply.count > 80 ? String(reply.prefix(80)) + "…" : reply
                status = .success("Connected! Gemini says: \"\(preview)\"")
                KeychainHelper.save(key)
                try? await Task.sleep(for: .seconds(1.2))
                dismiss()
            } catch {
                status = .failure(error.localizedDescription)
            }
        }
    }
}

#Preview {
    SettingsView()
}
