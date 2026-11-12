// 设置页：解析服务地址、访问口令、播放模式切换 + 健康检查
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    @State private var baseURL = ""
    @State private var token = ""
    @State private var healthStatus: String?
    @State private var checking = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("http://192.168.1.10:8787", text: $baseURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("解析服务地址")
                } footer: {
                    Text("填电脑的局域网 IP，手机与电脑需连同一 WiFi。\n不要填 127.0.0.1，那是手机自己。")
                }

                Section {
                    SecureField("可选，默认留空", text: $token)
                } header: {
                    Text("访问口令（token）")
                }

                Section {
                    Picker("播放模式", selection: modeBinding) {
                        ForEach(HGPlaybackMode.allCases) { mode in
                            VStack(alignment: .leading) {
                                Text(mode.label)
                                Text(mode.detail)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .tag(mode)
                        }
                    }
                    .pickerStyle(.inline)
                } header: {
                    Text("播放模式")
                }

                Section {
                    Button("保存") { save() }
                        .buttonStyle(.borderedProminent)

                    if checking {
                        HStack {
                            ProgressView()
                            Text("检查中…")
                                .foregroundColor(.secondary)
                        }
                    } else if let healthStatus {
                        Text(healthStatus)
                            .foregroundColor(healthStatus.contains("在线") ? .green : .red)
                    }
                }
            }
            .navigationTitle("设置")
            .onAppear {
                baseURL = appState.config.baseURL
                token = appState.config.token
            }
        }
    }

    private var modeBinding: Binding<HGPlaybackMode> {
        Binding(
            get: { appState.mode },
            set: { appState.mode = $0 }
        )
    }

    private func save() {
        appState.config = ResolverConfig(
            baseURL: baseURL,
            token: token,
            mode: appState.mode
        )
        checkHealth()
    }

    private func checkHealth() {
        checking = true
        healthStatus = nil
        Task {
            let client = HGServerClient(config: appState.config)
            let ok = await client.health()
            healthStatus = ok ? "服务在线 ✓" : "无法连接服务，请检查地址和网络"
            checking = false
        }
    }
}
