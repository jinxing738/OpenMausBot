// What little the phone gets to configure.
//
// Almost nothing, on purpose: companion settings, API keys and pairing all
// live on the computer, because losing the phone must not mean losing the
// ability to lock it out. This is a status page with an unpair button.
import SwiftUI
import CompanionCore

struct SettingsView: View {
    @EnvironmentObject private var session: Session
    @State private var confirmingSignOut = false

    var body: some View {
        Form {
            Section("电脑") {
                if let connection = session.connection {
                    LabeledContent("名称", value: connection.name)
                    LabeledContent("地址", value: "\(connection.host):\(connection.port)")
                }
                LabeledContent("连接状态", value: statusText)
            }

            Section {
                Button("解除此手机配对", role: .destructive) { confirmingSignOut = true }
            } footer: {
                Text("这里只会移除本机的配对。如果还要让电脑拒绝此手机连接，请在电脑端打开 OpenMausBot → 设置 → 手机和设备，移除这部手机。")
            }

            Section("手机端不管理") {
                Text("API 密钥、配对和本地虚拟机都在电脑上管理，此手机不能修改这些内容。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "解除此手机的配对？",
            isPresented: $confirmingSignOut,
            titleVisibility: .visible
        ) {
            Button("解除配对", role: .destructive) { session.signOut() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("重新连接时，需要用新的配对码。")
        }
    }

    private var statusText: String {
        switch session.status {
        case .live: return "已连接"
        case .connecting: return "正在连接…"
        case .unpaired: return "尚未配对"
        case .unauthorized: return "已在电脑端解除配对"
        case let .offline(reason): return reason
        }
    }
}
