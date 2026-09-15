import SwiftUI

struct ContentView: View {
    @StateObject private var manager = SpoofDPIManager.shared
    @StateObject private var settings = AppSettings.shared
    @StateObject private var launchManager = LaunchAtLoginManager.shared
    @StateObject private var updater = UpdateChecker.shared
    @State private var currentTab = 0
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("freewall")
                    .font(.headline)
                    .fontWeight(.bold)
                
                Spacer()
                
                Picker("", selection: $currentTab) {
                    Label("보호", systemImage: "shield.fill").tag(0)
                    Label("설정", systemImage: "gearshape").tag(1)
                    Label("로그", systemImage: "terminal").tag(2)
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)
            
            if updater.updateAvailable, let url = updater.releaseUrl {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(.blue)
                    Text("새로운 버전(\(updater.latestVersion)) 출시")
                        .font(.caption)
                        .fontWeight(.medium)
                    Spacer()
                    Button("다운로드") {
                        NSWorkspace.shared.open(url)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.12))
            }
            
            Divider()
            
            Group {
                if currentTab == 0 {
                    MinimalDashboardView(manager: manager, settings: settings, launchManager: launchManager)
                } else if currentTab == 1 {
                    MinimalSettingsView(manager: manager, settings: settings, launchManager: launchManager, updater: updater)
                } else {
                    MinimalLogsView(manager: manager)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 440, height: 480)
        .onAppear {
            updater.checkForUpdates(isUserInitiated: false)
        }
    }
}

struct MinimalDashboardView: View {
    @ObservedObject var manager: SpoofDPIManager
    @ObservedObject var settings: AppSettings
    @ObservedObject var launchManager: LaunchAtLoginManager
    
    var isAutoProtectActive: Binding<Bool> {
        Binding(
            get: { launchManager.isEnabled && settings.autoStartProtection },
            set: { newValue in
                launchManager.setEnabled(newValue)
                settings.autoStartProtection = newValue
            }
        )
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Button(action: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) {
                    manager.toggle()
                }
            }) {
                ZStack {
                    Circle()
                        .fill(manager.isRunning ? Color.green.opacity(0.12) : Color.secondary.opacity(0.08))
                        .frame(width: 140, height: 140)
                    
                    Circle()
                        .strokeBorder(manager.isRunning ? Color.green.opacity(0.4) : Color.secondary.opacity(0.2), lineWidth: 2)
                        .frame(width: 140, height: 140)
                    
                    Circle()
                        .fill(manager.isRunning ? Color.green : Color(nsColor: .controlBackgroundColor))
                        .frame(width: 104, height: 104)
                        .shadow(color: manager.isRunning ? Color.green.opacity(0.35) : Color.black.opacity(0.08), radius: 12, y: 4)
                    
                    Image(systemName: manager.isRunning ? "shield.checkered" : "power")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(manager.isRunning ? .white : .secondary)
                }
            }
            .buttonStyle(.plain)
            
            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(manager.isRunning ? Color.green : Color.secondary.opacity(0.5))
                        .frame(width: 8, height: 8)
                    Text(manager.isRunning ? "보호 활성화됨" : "보호 비활성화됨")
                        .font(.title3)
                        .fontWeight(.bold)
                }
            }
            
            HStack(spacing: 8) {
                InfoPill(text: "127.0.0.1:\(settings.port)")
                InfoPill(text: settings.httpsSplitMode == "chunk" ? "Chunk \(settings.httpsChunkSize)B" : settings.httpsSplitMode.uppercased())
                InfoPill(text: settings.dnsMode == "udp" ? "Quad9 9953" : "DoH")
            }
            
            Spacer()
            
            VStack(spacing: 0) {
                Toggle(isOn: isAutoProtectActive) {
                    Text("로그인 시 자동 보호 시작")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .toggleStyle(.switch)
            }
            .padding(14)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }
}

struct InfoPill: View {
    let text: String
    
    var body: some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(12)
    }
}

struct MinimalSettingsView: View {
    @ObservedObject var manager: SpoofDPIManager
    @ObservedObject var settings: AppSettings
    @ObservedObject var launchManager: LaunchAtLoginManager
    @ObservedObject var updater: UpdateChecker
    
    var body: some View {
        Form {
            Section("자동 시작") {
                Toggle("로그인 시 앱 자동 실행", isOn: Binding(
                    get: { launchManager.isEnabled },
                    set: { launchManager.setEnabled($0) }
                ))
                Toggle("실행 시 보호 자동 시작", isOn: $settings.autoStartProtection)
            }
            
            Section("프리셋") {
                HStack(spacing: 10) {
                    Button("Chunk 1B (Quad9)") {
                        settings.applyExtremeBypassPreset()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .controlSize(.small)
                    .disabled(manager.isRunning)
                    
                    Button("SNI (DoH)") {
                        settings.applyStandardPreset()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(manager.isRunning)
                }
            }
            
            Section("네트워크 및 프록시") {
                TextField("로컬 포트", value: $settings.port, format: .number)
                    .disabled(manager.isRunning)
                Toggle("macOS 시스템 프록시 자동 구성", isOn: $settings.autoConfigureNetwork)
                    .disabled(manager.isRunning)
            }
            
            Section("DNS 및 패킷 파편화") {
                Picker("DNS 방식", selection: $settings.dnsMode) {
                    Text("UDP").tag("udp")
                    Text("DoH").tag("https")
                    Text("시스템").tag("system")
                }
                .pickerStyle(.segmented)
                .disabled(manager.isRunning)
                
                if settings.dnsMode == "udp" {
                    TextField("DNS 서버", text: $settings.dnsAddr)
                        .disabled(manager.isRunning)
                } else if settings.dnsMode == "https" || settings.dnsMode == "doh" {
                    TextField("DoH 주소", text: $settings.dnsHttpsUrl)
                        .disabled(manager.isRunning)
                }
                
                Picker("분할 방식", selection: $settings.httpsSplitMode) {
                    Text("Chunk").tag("chunk")
                    Text("SNI").tag("sni")
                    Text("Random").tag("random")
                    Text("None").tag("none")
                }
                .disabled(manager.isRunning)
                
                if settings.httpsSplitMode == "chunk" {
                    Stepper("청크 크기: \(settings.httpsChunkSize) B", value: $settings.httpsChunkSize, in: 1...255)
                        .disabled(manager.isRunning)
                }
                
                Toggle("패킷 순서 섞기 (Disorder)", isOn: $settings.httpsDisorder)
                    .disabled(manager.isRunning)
            }
            
            Section("버전 및 업데이트") {
                HStack {
                    Text("현재 버전")
                    Spacer()
                    Text("v\(updater.currentVersion)")
                        .foregroundStyle(.secondary)
                }
                
                HStack {
                    Button(action: {
                        updater.checkForUpdates(isUserInitiated: true)
                    }) {
                        HStack(spacing: 6) {
                            if updater.isChecking {
                                ProgressView()
                                    .controlSize(.mini)
                            }
                            Text("업데이트 확인")
                        }
                    }
                    .disabled(updater.isChecking)
                    
                    Spacer()
                    
                    if let url = updater.releaseUrl, updater.updateAvailable {
                        Button("다운로드") {
                            NSWorkspace.shared.open(url)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                        .controlSize(.small)
                    }
                }
                
                if !updater.statusMessage.isEmpty {
                    Text(updater.statusMessage)
                        .font(.caption2)
                        .foregroundStyle(updater.updateAvailable ? .blue : .secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 8)
    }
}

struct MinimalLogsView: View {
    @ObservedObject var manager: SpoofDPIManager
    @State private var autoScroll = true
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("\(manager.logs.count)개 라인")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle("자동 스크롤", isOn: $autoScroll)
                    .toggleStyle(.checkbox)
                    .font(.caption2)
                Button("복사") {
                    let fullText = manager.logs.map { $0.text }.joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(fullText, forType: .string)
                }
                .controlSize(.mini)
                Button("비우기") {
                    manager.clearLogs()
                }
                .controlSize(.mini)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(manager.logs) { entry in
                            Text(entry.text)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(entry.isError ? Color.red : Color.primary)
                                .textSelection(.enabled)
                                .id(entry.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                }
                .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .onChange(of: manager.logs.count) {
                    if autoScroll, let last = manager.logs.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView()
}



