import Foundation
import Combine
import SwiftUI
import ServiceManagement

class LaunchAtLoginManager: ObservableObject {
    static let shared = LaunchAtLoginManager()
    
    @Published var isEnabled: Bool = false
    
    init() {
        refreshStatus()
    }
    
    func refreshStatus() {
        if #available(macOS 13.0, *) {
            self.isEnabled = (SMAppService.mainApp.status == .enabled)
        }
    }
    
    func setEnabled(_ enable: Bool) {
        guard #available(macOS 13.0, *) else { return }
        do {
            if enable {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            self.isEnabled = enable
        } catch {
            print("LaunchAtLogin error: \(error.localizedDescription)")
            refreshStatus()
        }
    }
}

class AppSettings: ObservableObject {
    static let shared = AppSettings()
    
    @AppStorage("proxyPort") var port: Int = 8080
    @AppStorage("dnsMode") var dnsMode: String = "udp"
    @AppStorage("dnsAddr") var dnsAddr: String = "9.9.9.9:9953"
    @AppStorage("dnsHttpsUrl") var dnsHttpsUrl: String = "https://dns.google/dns-query"
    @AppStorage("httpsSplitMode") var httpsSplitMode: String = "chunk"
    @AppStorage("httpsChunkSize") var httpsChunkSize: Int = 1
    @AppStorage("httpsDisorder") var httpsDisorder: Bool = true
    @AppStorage("autoConfigureNetwork") var autoConfigureNetwork: Bool = true
    @AppStorage("autoStartProtection") var autoStartProtection: Bool = false
    @AppStorage("customBinaryPath") var customBinaryPath: String = ""
    @AppStorage("logLevel") var logLevel: String = "info"
    
    func applyExtremeBypassPreset() {
        dnsMode = "udp"
        dnsAddr = "9.9.9.9:9953"
        httpsSplitMode = "chunk"
        httpsChunkSize = 1
        httpsDisorder = true
    }
    
    func applyStandardPreset() {
        dnsMode = "https"
        dnsHttpsUrl = "https://dns.google/dns-query"
        httpsSplitMode = "sni"
        httpsChunkSize = 35
        httpsDisorder = false
    }
}

struct LogEntry: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let text: String
    let isError: Bool
}

@MainActor
class SpoofDPIManager: ObservableObject {
    static let shared = SpoofDPIManager()
    
    @Published var isRunning: Bool = false
    @Published var statusMessage: String = "중지됨"
    @Published var logs: [LogEntry] = []
    @Published var detectedBinaryPath: String? = nil
    
    private var process: Process?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private let settings = AppSettings.shared
    private let maxLogCount = 1000
    
    init() {
        self.detectedBinaryPath = findBinaryPath()
        if settings.autoStartProtection {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.start()
            }
        }
    }
    
    func findBinaryPath() -> String? {
        if !settings.customBinaryPath.isEmpty && FileManager.default.isExecutableFile(atPath: settings.customBinaryPath) {
            return settings.customBinaryPath
        }
        
        if let bundlePath = Bundle.main.path(forResource: "spoofdpi", ofType: nil),
           FileManager.default.isExecutableFile(atPath: bundlePath) {
            return bundlePath
        }
        
        let candidatePaths = [
            "/opt/homebrew/bin/spoofdpi",
            "/usr/local/bin/spoofdpi",
            "/usr/bin/spoofdpi"
        ]
        
        for path in candidatePaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        
        return nil
    }
    
    func start() {
        guard !isRunning else { return }
        
        killExistingProcesses()
        
        guard let binaryPath = findBinaryPath() else {
            appendLog("error: executable binary not found", isError: true)
            statusMessage = "바이너리 없음"
            return
        }
        
        self.detectedBinaryPath = binaryPath
        
        var dnsModeArg = settings.dnsMode
        if dnsModeArg == "doh" { dnsModeArg = "https" }
        if dnsModeArg == "sys" { dnsModeArg = "system" }
        
        var arguments: [String] = [
            "--no-tui",
            "--listen-addr", "127.0.0.1:\(settings.port)",
            "--dns-mode", dnsModeArg,
            "--https-split-mode", settings.httpsSplitMode,
            "--log-level", settings.logLevel,
            "--tcp-timeout", "0"
        ]
        
        if dnsModeArg == "udp" {
            arguments.append(contentsOf: ["--dns-addr", settings.dnsAddr])
        }
        
        if dnsModeArg == "https" {
            arguments.append(contentsOf: ["--dns-https-url", settings.dnsHttpsUrl])
        }
        
        if settings.httpsSplitMode == "chunk" {
            arguments.append(contentsOf: ["--https-chunk-size", "\(settings.httpsChunkSize)"])
        }
        
        if settings.httpsDisorder {
            arguments.append("--https-disorder")
        }
        
        if settings.autoConfigureNetwork {
            arguments.append("--auto-configure-network")
        }
        
        appendLog("$ spoofdpi " + arguments.joined(separator: " "), isError: false)
        
        let newProcess = Process()
        newProcess.executableURL = URL(fileURLWithPath: binaryPath)
        newProcess.arguments = arguments
        
        let outPipe = Pipe()
        let errPipe = Pipe()
        newProcess.standardOutput = outPipe
        newProcess.standardError = errPipe
        
        self.process = newProcess
        self.outputPipe = outPipe
        self.errorPipe = errPipe
        
        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let output = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor [weak self] in
                self?.processLogOutput(output, isError: false)
            }
        }
        
        errPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let output = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor [weak self] in
                self?.processLogOutput(output, isError: true)
            }
        }
        
        newProcess.terminationHandler = { [weak self] proc in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.isRunning = false
                self.statusMessage = "중지됨 (\(proc.terminationStatus))"
                self.appendLog("process exited with code \(proc.terminationStatus)", isError: proc.terminationStatus != 0)
                
                if self.settings.autoConfigureNetwork {
                    self.resetSystemProxy()
                }
                self.cleanupProcessHandles()
            }
        }
        
        do {
            try newProcess.run()
            self.isRunning = true
            self.statusMessage = "실행 중 (\(settings.port))"
        } catch {
            self.isRunning = false
            self.statusMessage = "실행 실패"
            appendLog("failed to start: \(error.localizedDescription)", isError: true)
            cleanupProcessHandles()
        }
    }
    
    func stop() {
        guard let process = self.process, process.isRunning else {
            self.isRunning = false
            self.statusMessage = "중지됨"
            if settings.autoConfigureNetwork {
                resetSystemProxy()
            }
            return
        }
        
        appendLog("shutting down...", isError: false)
        statusMessage = "종료 중..."
        
        kill(process.processIdentifier, SIGINT)
        
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self, let proc = self.process, proc.isRunning else { return }
                self.appendLog("killing process (SIGKILL)", isError: false)
                proc.terminate()
                if self.settings.autoConfigureNetwork {
                    self.resetSystemProxy()
                }
            }
        }
    }
    
    func toggle() {
        if isRunning {
            stop()
        } else {
            start()
        }
    }
    
    private func processLogOutput(_ text: String, isError: Bool) {
        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                appendLog(trimmed, isError: isError)
            }
        }
    }
    
    private func appendLog(_ text: String, isError: Bool) {
        let entry = LogEntry(timestamp: Date(), text: text, isError: isError)
        logs.append(entry)
        if logs.count > maxLogCount {
            logs.removeFirst(logs.count - maxLogCount)
        }
    }
    
    func clearLogs() {
        logs.removeAll()
    }
    
    private func cleanupProcessHandles() {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        outputPipe = nil
        errorPipe = nil
        process = nil
    }
    
    private func killExistingProcesses() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        task.arguments = ["-x", "spoofdpi"]
        try? task.run()
        task.waitUntilExit()
    }
    
    func resetSystemProxy() {
        DispatchQueue.global().async {
            let services = self.getNetworkServices()
            for service in services {
                let webCmd = Process()
                webCmd.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
                webCmd.arguments = ["-setwebproxystate", service, "off"]
                try? webCmd.run()
                webCmd.waitUntilExit()
                
                let secureCmd = Process()
                secureCmd.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
                secureCmd.arguments = ["-setsecurewebproxystate", service, "off"]
                try? secureCmd.run()
                secureCmd.waitUntilExit()
            }
        }
    }
    
    nonisolated private func getNetworkServices() -> [String] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        task.arguments = ["-listallnetworkservices"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        try? task.run()
        task.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return ["Wi-Fi", "Ethernet"] }
        
        let lines = output.components(separatedBy: .newlines)
        return lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return !trimmed.isEmpty && !trimmed.contains("*")
        }
    }
}

