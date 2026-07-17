#if os(macOS)
import Combine
import Foundation
import WinLiftCore

enum VMRuntimeError: LocalizedError {
    case anotherMachineIsRunning
    case unsupportedHostArchitecture
    case processDidNotStart(String)

    var errorDescription: String? {
        switch self {
        case .anotherMachineIsRunning:
            return "当前已有虚拟机在运行。MVP 暂时一次只运行一台。"
        case .unsupportedHostArchitecture:
            return "WinLift 当前只支持 Apple Silicon Mac 上的 Windows 11 ARM64。"
        case let .processDidNotStart(message):
            return "QEMU 启动失败：\(message)"
        }
    }
}

@MainActor
final class QEMUProcessController: ObservableObject {
    @Published private(set) var activeMachineID: UUID?
    @Published private(set) var lastMachineID: UUID?
    @Published private(set) var state: VMRuntimeState = .stopped
    @Published private(set) var logText = ""

    private var process: Process?
    private var qmpInput: Pipe?
    private var qmpOutput: Pipe?
    private var standardError: Pipe?
    private var logHandle: FileHandle?
    private var runtimePIDURL: URL?
    private var startupGraceTask: Task<Void, Never>?
    private var qmpCapabilitiesSent = false
    private var qmpGreetingBuffer = ""
    private var expectedTermination = false
    private let maximumLogCharacters = 60_000

    var canStart: Bool {
        process == nil
    }

    var canPause: Bool {
        state == .running && qmpCapabilitiesSent
    }

    var canResume: Bool {
        state == .paused && qmpCapabilitiesSent
    }

    var canRequestShutdown: Bool {
        (state == .running || state == .paused) && qmpCapabilitiesSent
    }

    func start(
        machine: VirtualMachine,
        layout: VMStorageLayout,
        installation: QEMUInstallation
    ) throws {
        guard process == nil else {
            throw VMRuntimeError.anotherMachineIsRunning
        }

#if !arch(arm64)
        throw VMRuntimeError.unsupportedHostArchitecture
#else
        let process = Process()
        let qmpInput = Pipe()
        let qmpOutput = Pipe()
        let standardError = Pipe()

        process.executableURL = installation.executableURL
        process.arguments = QEMUCommandBuilder.arguments(
            machine: machine,
            layout: layout,
            installation: installation
        )
        process.currentDirectoryURL = layout.bundleURL(for: machine.id)
        process.standardInput = qmpInput
        process.standardOutput = qmpOutput
        process.standardError = standardError

        self.process = process
        self.qmpInput = qmpInput
        self.qmpOutput = qmpOutput
        self.standardError = standardError
        activeMachineID = machine.id
        lastMachineID = machine.id
        state = .starting
        logText = ""
        qmpCapabilitiesSent = false
        qmpGreetingBuffer = ""
        expectedTermination = false
        runtimePIDURL = layout.runtimePIDURL(for: machine.id)
        prepareLogFile(at: layout.logURL(for: machine.id))
        appendLog("[WinLift] 正在启动 \(machine.name)…\n")

        qmpOutput.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                // EOF：不摘除 handler 会让空数据回调持续触发。
                handle.readabilityHandler = nil
                return
            }
            Task { @MainActor in
                self?.consumeQMPOutput(data)
            }
        }

        standardError.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            Task { @MainActor in
                self?.consumeStandardError(data)
            }
        }

        process.terminationHandler = { [weak self] terminatedProcess in
            let status = terminatedProcess.terminationStatus
            Task { @MainActor in
                self?.handleTermination(status: status)
            }
        }

        do {
            try process.run()
        } catch {
            cleanUpPipesAndProcess()
            state = .failed(error.localizedDescription)
            throw VMRuntimeError.processDidNotStart(error.localizedDescription)
        }

        // QMP normally sends its greeting immediately. If a QEMU build delays
        // that greeting, the VM is still considered running after this grace period.
        startupGraceTask?.cancel()
        startupGraceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled, let self else { return }
            if self.process != nil, self.state == .starting {
                self.state = .running
            }
        }
#endif
    }

    func pause() {
        guard canPause else { return }
        sendQMPCommand("stop")
        state = .paused
        appendLog("[WinLift] 已请求暂停虚拟机。\n")
    }

    func resume() {
        guard canResume else { return }
        sendQMPCommand("cont")
        state = .running
        appendLog("[WinLift] 已请求恢复虚拟机。\n")
    }

    func requestShutdown() {
        guard process != nil, canRequestShutdown else { return }
        if state == .paused {
            sendQMPCommand("cont")
        }
        expectedTermination = true
        state = .stopping
        sendQMPCommand("system_powerdown")
        appendLog("[WinLift] 已发送 ACPI 关机请求，请等待 Windows 正常退出。\n")
    }

    func forceStop() {
        guard let process else { return }
        expectedTermination = true
        appendLog("[WinLift] 正在强制终止 QEMU；未写入的数据可能丢失。\n")
        process.terminate()
    }

    func clearLog() {
        logText = ""
    }

    private func consumeQMPOutput(_ data: Data) {
        let text = String(decoding: data, as: UTF8.self)
        appendLog("[QMP] \(text)")
        qmpGreetingBuffer += text
        if qmpGreetingBuffer.count > 8_192 {
            qmpGreetingBuffer = String(qmpGreetingBuffer.suffix(8_192))
        }

        if qmpGreetingBuffer.contains("\"QMP\""), !qmpCapabilitiesSent {
            qmpCapabilitiesSent = true
            sendQMPCommand("qmp_capabilities")
            if state == .starting {
                state = .running
            }
        }
    }

    private func consumeStandardError(_ data: Data) {
        appendLog(String(decoding: data, as: UTF8.self))
    }

    private func sendQMPCommand(_ command: String) {
        guard let handle = qmpInput?.fileHandleForWriting else { return }
        let payload = "{\"execute\":\"\(command)\"}\n"
        guard let data = payload.data(using: .utf8) else { return }

        do {
            try handle.write(contentsOf: data)
        } catch {
            appendLog("[WinLift] QMP 命令发送失败：\(error.localizedDescription)\n")
        }
    }

    private func prepareLogFile(at url: URL) {
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }

        do {
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            logHandle = handle
        } catch {
            logHandle = nil
            logText += "[WinLift] 无法写入日志文件：\(error.localizedDescription)\n"
        }
    }

    private func appendLog(_ text: String) {
        logText += text
        if logText.count > maximumLogCharacters {
            logText = String(logText.suffix(maximumLogCharacters))
        }

        if let data = text.data(using: .utf8) {
            try? logHandle?.write(contentsOf: data)
        }
    }

    private func handleTermination(status: Int32) {
        let wasExpected = expectedTermination
        appendLog("[WinLift] QEMU 已退出（状态码 \(status)）。\n")
        cleanUpPipesAndProcess()

        if status == 0 || wasExpected {
            state = .stopped
        } else {
            state = .failed("QEMU 退出状态码：\(status)")
        }
    }

    private func cleanUpPipesAndProcess() {
        startupGraceTask?.cancel()
        startupGraceTask = nil
        qmpOutput?.fileHandleForReading.readabilityHandler = nil
        standardError?.fileHandleForReading.readabilityHandler = nil
        try? qmpInput?.fileHandleForWriting.close()
        try? qmpOutput?.fileHandleForReading.close()
        try? standardError?.fileHandleForReading.close()
        try? logHandle?.close()
        if let runtimePIDURL {
            try? FileManager.default.removeItem(at: runtimePIDURL)
        }

        process = nil
        qmpInput = nil
        qmpOutput = nil
        standardError = nil
        logHandle = nil
        runtimePIDURL = nil
        activeMachineID = nil
        qmpCapabilitiesSent = false
        qmpGreetingBuffer = ""
        expectedTermination = false
    }
}
#endif
