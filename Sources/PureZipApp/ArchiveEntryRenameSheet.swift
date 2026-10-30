import AppKit
import SwiftUI
import ArchiveCore

/// Modal sheet for renaming an entry inside an archive.
public struct ArchiveEntryRenameSheet: View {
    @ObservedObject var session: ArchiveBrowsingSession
    @State private var inputName: String = ""
    @FocusState private var isFieldFocused: Bool

    public init(session: ArchiveBrowsingSession) {
        self.session = session
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(red: 0.05, green: 0.48, blue: 0.98).opacity(0.15))
                        .frame(width: 36, height: 36)

                    Image(systemName: session.entryBeingRenamed?.type == .directory ? "folder.fill" : "pencil")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color(red: 0.05, green: 0.48, blue: 0.98))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("重命名条目")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.primary)

                    if let currentName = session.entryBeingRenamed?.name {
                        Text("当前名称: \(currentName)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()
            }

            // Input Row
            VStack(alignment: .leading, spacing: 6) {
                Text("新名称")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField("输入新名称...", text: $inputName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(7)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 1)
                    )
                    .focused($isFieldFocused)
                    .onSubmit {
                        submitRename()
                    }
            }

            Divider()
                .opacity(0.6)

            // Bottom Buttons
            HStack(spacing: 12) {
                Spacer()

                Button("取消") {
                    session.cancelRename()
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(7)
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Color(NSColor.separatorColor).opacity(0.4), lineWidth: 1)
                )

                Button {
                    submitRename()
                } label: {
                    Text("重命名")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(
                            LinearGradient(
                                colors: [Color(red: 0.18, green: 0.48, blue: 0.98), Color(red: 0.05, green: 0.48, blue: 0.98)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(Capsule())
                        .shadow(color: Color(red: 0.05, green: 0.48, blue: 0.98).opacity(0.3), radius: 4, y: 1.5)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                .disabled(inputName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            if let entry = session.entryBeingRenamed {
                inputName = entry.name
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isFieldFocused = true
            }
        }
    }

    private func submitRename() {
        let trimmed = inputName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        session.confirmRename(newName: trimmed)
    }
}
