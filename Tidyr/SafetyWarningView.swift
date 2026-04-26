import SwiftUI

// Shown when the safety checker detects a risky folder
struct SafetyWarningView: View {
    let title: String
    let detail: String
    let isDanger: Bool
    let onProceed: () -> Void
    let onCancel: () -> Void

    var iconName: String  { isDanger ? "xmark.octagon.fill"      : "exclamationmark.triangle.fill" }
    var iconColor: Color  { isDanger ? .red                       : .orange }
    var proceedLabel: String { isDanger ? "Analyze Anyway (Not Recommended)" : "Analyze Anyway" }

    var body: some View {
        VStack(spacing: 0) {

            // Icon + title
            VStack(spacing: 14) {
                Image(systemName: iconName)
                    .font(.system(size: 52))
                    .foregroundStyle(iconColor)
                    .padding(.top, 32)

                Text(title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 20)

            Divider()

            // Detail
            Text(detail)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(28)

            Divider()

            // Buttons
            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                Spacer()

                if isDanger {
                    Button(proceedLabel, action: onProceed)
                        .buttonStyle(.bordered)
                        .foregroundStyle(.red)
                        .controlSize(.large)
                } else {
                    Button(proceedLabel, action: onProceed)
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }
            }
            .padding(24)
        }
        .frame(width: 460)
    }
}

#Preview {
    SafetyWarningView(
        title: "This looks like an Xcode project",
        detail: "Xcode projects depend on exact file paths. Moving or renaming source files here will cause build errors.",
        isDanger: false,
        onProceed: {},
        onCancel: {}
    )
}
