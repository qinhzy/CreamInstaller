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
public final class QEMUProcessController: ObservableObject {
    @Published private(set) var activeMachineID: UUID?
    @Published private(set) var lastMachineID: UUID?
    @Published public private(set) var state: VMRuntimeState = .stopped
    @Published private(set) var startedAt: Date?
    @Published private(set) var logText = ""

    private var process: Process?
    private var qmpInput: Pipe?
    private var qmpOutput: Pipe?
    private var standardError: Pipe?
    private var logHandle: FileHandle?
    private var runtimePIDURL: URL?
    private var startupGraceTask: Task<Void, Never>?
    private var logFlushTask: Task<Void, Never>?
    private var qmpCapabilitiesSent = false
    private var qmpParser = QMPStreamParser()
    private var expectedTermination = false
    private var pendingLogText = ""
    private let maximumLogCharacters = 60_000
    private let logPublishIntervalNanoseconds: UInt64 = 250_000_000

    var canStart: Bool {
        process == nil
    }

    public var canPause: Bool {
        state == .running && qmpCapabilitiesSent
    }

    public var canResume: Bool {
        state == .paused && qmpCapabilitiesSent
    }

    public var canRequestShutdown: Bool {
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
        pendingLogText = ""
        logFlushTask?.cancel()
        logFlushTask = nil
        qmpCapabilitiesSent = false
        qmpParser = QMPStreamParser()
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
            Task { @MainActor [weak self] in
                self?.consumeQMPOutput(data)
            }
        }

        standardError.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            Task { @MainActor [weak self] in
                self?.consumeStandardError(data)
            }
        }

        process.terminationHandler = { [weak self] terminatedProcess in
            let status = terminatedProcess.terminationStatus
            Task { @MainActor [weak self] in
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
        startupGraceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled, let self else { return }
            if self.process != nil, self.state == .starting {
                self.state = .running
                if self.startedAt == nil {
                    self.startedAt = Date()
                }
            }
        }
#endif
    }

    public func pause() {
        guard canPause else { return }
        guard sendQMPCommand("stop") else { return }
        state = .paused
        appendLog("[WinLift] 已请求暂停虚拟机。\n")
    }

    public func resume() {
        guard canResume else { return }
        guard sendQMPCommand("cont") else { return }
        state = .running
        appendLog("[WinLift] 已请求恢复虚拟机。\n")
    }

    public func requestShutdown() {
        guard process != nil, canRequestShutdown else { return }
        if state == .paused {
            guard sendQMPCommand("cont") else { return }
            // QEMU has accepted the resume request. If the following powerdown
            // write fails, do not leave the UI claiming that the VM is paused.
            state = .running
        }
        guard sendQMPCommand("system_powerdown") else { return }
        expectedTermination = true
        state = .stopping
        appendLog("[WinLift] 已发送 ACPI 关机请求，请等待 Windows 正常退出。\n")
    }

    public func forceStop() {
        guard let process else { return }
        expectedTermination = true
        appendLog("[WinLift] 正在强制终止 QEMU；未写入的数据可能丢失。\n")
        process.terminate()
    }

    func clearLog() {
        logFlushTask?.cancel()
        logFlushTask = nil
        pendingLogText = ""
        logText = ""
    }

    /// 一台虚拟机被删除后，清掉它遗留的日志与失败状态显示。
    func forget(machineID: UUID) {
        guard activeMachineID != machineID else { return }
        if lastMachineID == machineID {
            lastMachineID = nil
            logText = ""
            if !state.isActive {
                state = .stopped
            }
        }
    }

    private func consumeQMPOutput(_ data: Data) {
        let text = String(decoding: data, as: UTF8.self)
        appendLog("[QMP] \(text)")

        for message in qmpParser.consume(data) {
            switch message {
            case .greeting:
                if !qmpCapabilitiesSent, sendQMPCommand("qmp_capabilities") {
                    qmpCapabilitiesSent = true
                    if state == .starting {
                        state = .running
                    }
                    if startedAt == nil {
                        startedAt = Date()
                    }
                }

            case let .event(event):
                state = QMPStateReducer.state(after: message, currentState: state)
                if ["SHUTDOWN", "POWERDOWN"].contains(event.uppercased()) {
                    expectedTermination = true
                }

            case .commandReturn, .other:
                break
            }
        }
    }

    private func consumeStandardError(_ data: Data) {
        appendLog(String(decoding: data, as: UTF8.self))
    }

    @discardableResult
    private func sendQMPCommand(_ command: String) -> Bool {
        guard let handle = qmpInput?.fileHandleForWriting else {
            appendLog("[WinLift] QMP 命令发送失败：控制通道不可用。\n")
            return false
        }
        let payload = "{\"execute\":\"\(command)\"}\n"
        guard let data = payload.data(using: .utf8) else {
            appendLog("[WinLift] QMP 命令发送失败：无法编码命令。\n")
            return false
        }

        do {
            try handle.write(contentsOf: data)
            return true
        } catch {
            appendLog("[WinLift] QMP 命令发送失败：\(error.localizedDescription)\n")
            return false
        }
    }

    private func prepareLogFile(at url: URL) {
        do {
            logHandle = try QEMULogFile.openForAppending(at: url)
        } catch {
            logHandle = nil
            queueLogForDisplay("[WinLift] 无法写入日志文件：\(error.localizedDescription)\n")
        }
    }

    private func appendLog(_ text: String) {
        queueLogForDisplay(text)

        guard let data = text.data(using: .utf8), let logHandle else { return }
        do {
            try logHandle.write(contentsOf: data)
        } catch {
            try? logHandle.close()
            self.logHandle = nil
            queueLogForDisplay("[WinLift] 日志文件写入失败：\(error.localizedDescription)\n")
        }
    }

    private func queueLogForDisplay(_ text: String) {
        pendingLogText += text
        guard logFlushTask == nil else { return }

        logFlushTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: self?.logPublishIntervalNanoseconds ?? 0)
            } catch {
                return
            }
            guard !Task.isCancelled, let self else { return }
            self.flushPendingLog()
        }
    }

    private func flushPendingLog() {
        logFlushTask = nil
        guard !pendingLogText.isEmpty else { return }

        logText += pendingLogText
        pendingLogText = ""
        if logText.count > maximumLogCharacters {
            logText = String(logText.suffix(maximumLogCharacters))
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
        logFlushTask?.cancel()
        logFlushTask = nil
        flushPendingLog()
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
        startedAt = nil
        qmpCapabilitiesSent = false
        qmpParser = QMPStreamParser()
        expectedTermination = false
    }
}
#endif
