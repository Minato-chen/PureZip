import AppKit
import SwiftUI

/// Native macOS password prompt sheet for encrypted archives.
public struct ArchivePasswordPromptView: View {
    @ObservedObject var session: ArchiveBrowsingSession
    @State private var passwordText: String = ""
    @State private var isShowingPlainText: Bool = false
    @FocusState private var isFieldFocused: Bool

    public init(session: ArchiveBrowsingSession) {
        self.session = session
    }

    public var body: some View {
        VStack(spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 6) {
                    Text("需要解压密码")
                        .font(.headline)

                    Text("「\(session.currentArchiveURL?.lastPathComponent ?? "归档")」已加密，请输入密码以解密浏览或提取文件。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    if isShowingPlainText {
                        TextField("请输入密码", text: $passwordText)
                            .textFieldStyle(.roundedBorder)
                            .focused($isFieldFocused)
                    } else {
                        SecureField("请输入密码", text: $passwordText)
                            .textFieldStyle(.roundedBorder)
                            .focused($isFieldFocused)
                    }

                    Button {
                        isShowingPlainText.toggle()
                    } label: {
                        Image(systemName: isShowingPlainText ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(isShowingPlainText ? "隐藏明文" : "显示明文")
                }

                if let err = session.passwordPromptErrorMessage {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.red)
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }

            HStack {
                Button("取消") {
                    session.cancelPasswordPrompt()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("解锁并打开") {
                    submit()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(passwordText.isEmpty)
            }
        }
        .padding(22)
        .frame(width: 420)
        .onAppear {
            isFieldFocused = true
        }
    }

    private func submit() {
        let pwd = passwordText
        session.submitPassword(pwd)
    }
}
