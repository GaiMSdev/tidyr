import SwiftUI

struct WelcomeView: View {
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 18) {
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.system(size: 68))
                    .foregroundStyle(.white)
                    .frame(width: 110, height: 110)
                    .background(
                        LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 28)
                    )
                    .padding(.top, 36)

                Text("Welcome to Tidyr")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Organize files in plain language. Tidyr suggests the cleanup, and you decide what actually happens.")
                    .foregroundStyle(.secondary)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 32)

            VStack(spacing: 14) {
                Label("Visible buttons in the sidebar for adding folders and setting up AI", systemImage: "sidebar.left")
                Label("Ask for help in everyday language instead of using rules or scripts", systemImage: "text.bubble")
                Label("Review every suggestion before any file is moved", systemImage: "checkmark.shield")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 32)
            .padding(.bottom, 28)

            Divider()

            VStack(alignment: .leading, spacing: 24) {
                WelcomeStep(
                    icon: "key.fill", color: .orange,
                    title: "Set up your free AI key",
                    detail: "Tidyr uses Google Gemini. You can create a key in Google AI Studio and store it securely in your Mac's Keychain."
                )
                WelcomeStep(
                    icon: "folder.badge.plus", color: .blue,
                    title: "Add a folder you want help with",
                    detail: "Choose any folder on your Mac, from Downloads to an Obsidian vault. The Add Folder button is always visible in the sidebar."
                )
                WelcomeStep(
                    icon: "checkmark.seal.fill", color: .green,
                    title: "Describe the result you want",
                    detail: "Ask Tidyr in plain language, then review the suggestions. Nothing moves until you approve it."
                )
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 28)

            Divider()

            // Footer
            HStack {
                Button("Get free API key →") {
                    NSWorkspace.shared.open(URL(string: "https://aistudio.google.com/app/apikey")!)
                }
                .buttonStyle(.link)

                Spacer()

                Button("Get Started") {
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(24)
        }
        .frame(width: 520)
    }
}

private struct WelcomeStep: View {
    let icon: String
    let color: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(color, in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(title).fontWeight(.semibold)
                Text(detail).foregroundStyle(.secondary).font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    WelcomeView(isPresented: .constant(true))
}
