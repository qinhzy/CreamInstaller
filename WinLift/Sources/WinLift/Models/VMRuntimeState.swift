import Foundation

enum VMRuntimeState: Equatable {
    case stopped
    case starting
    case running
    case paused
    case stopping
    case failed(String)

    var title: String {
        switch self {
        case .stopped:
            return "已停止"
        case .starting:
            return "正在启动"
        case .running:
            return "运行中"
        case .paused:
            return "已暂停"
        case .stopping:
            return "正在关机"
        case .failed:
            return "启动失败"
        }
    }

    var isActive: Bool {
        switch self {
        case .stopped, .failed:
            return false
        case .starting, .running, .paused, .stopping:
            return true
        }
    }
}
