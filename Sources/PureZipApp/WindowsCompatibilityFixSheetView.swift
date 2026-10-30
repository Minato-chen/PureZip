import AppKit
import SwiftUI
import ArchiveCore

/// Interactive modal sheet for reviewing and fixing Windows-incompatible filenames before compression.
/// Allows users to review Windows incompatible filenames (DOS devices, trailing dots/spaces, illegal chars),
/// customize their names for the archive, restore suggestions, and compress without altering disk files.
public struct WindowsCompatibilityFixSheetView: View {
    @ObservedObject var model: ArchiveCreationViewModel
    let onCancel: () -> Void
    let onConfirm: () -> Void

    public init(
        model: ArchiveCreationViewModel,
        onCancel: @escaping () -> Void,
        onConfirm: @escaping () -> Void
    ) {
        self.model = model
        self.onCancel = onCancel
        self.onConfirm = onConfirm
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.orange.opacity(0.14))
                        .frame(width: 36, height: 36)

                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.orange)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("修正不兼容文件名")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.primary)

                    Text("以下文件名在 Windows 中可能无法正常使用。请检查或修改建议名称。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            // Subheader: Count badge & Restore Button
            HStack {
                Text("待确认：\(model.compatibilityIssues.count)个文件名")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    model.restoreAllSuggestions()
                } label: {
                    Text("恢复全部建议")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(red: 0.05, green: 0.48, blue: 0.98))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 2)

            // Scrollable List of Incompatible Filename Cards
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 10) {
                    ForEach(model.compatibilityIssues) { issue in
                        compatibilityCard(for: issue)
                    }
                }
                .padding(.trailing, 2)
            }
            .frame(maxHeight: 340)

            Divider()
                .opacity(0.6)

            // Footer
            HStack(spacing: 12) {
                // Info label
                HStack(spacing: 5) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    Text("只会修改压缩包内的名称，源文件不受影响。")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Back Button
                Button {
                    onCancel()
                } label: {
                    Text("← 回到创建设置")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(7)
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(Color(NSColor.separatorColor).opacity(0.4), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                // Confirm and Continue Button
                Button {
                    onConfirm()
                } label: {
                    Text("→ 使用这些名称并继续")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(
                            LinearGradient(
                                colors: [Color(red: 0.22, green: 0.62, blue: 1.0), Color(red: 0.05, green: 0.48, blue: 0.98)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(Capsule())
                        .shadow(color: Color(red: 0.05, green: 0.48, blue: 0.98).opacity(0.35), radius: 5, y: 1.5)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 580, height: 490)
        .background(Color(NSColor.windowBackgroundColor))
    }

    @ViewBuilder
    private func compatibilityCard(for issue: ArchiveCreationPurpose.WindowsCompatibilityIssue) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            // Row 1: Original Path inside archive
            Text(issue.originalPath)
                .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)

            // Row 2: Incompatibility Reason
            Text(issue.reasonDescription)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)

            // Row 3: New Name input
            HStack(spacing: 8) {
                Text("新名称")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 42, alignment: .leading)

                TextField("", text: binding(for: issue))
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5, weight: .medium))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 1)
                    )
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(9)
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(Color(NSColor.separatorColor).opacity(0.35), lineWidth: 1)
        )
    }

    private func binding(for issue: ArchiveCreationPurpose.WindowsCompatibilityIssue) -> Binding<String> {
        Binding(
            get: {
                model.customizedFilenames[issue.id] ?? issue.suggestedFilename
            },
            set: { newValue in
                model.customizedFilenames[issue.id] = newValue
            }
        )
    }
}
