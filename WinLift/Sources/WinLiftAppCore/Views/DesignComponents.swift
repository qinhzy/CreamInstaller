#if os(macOS)
import SwiftUI

/// 系统设置风格的行首图标芯片：小圆角方块 + 白色 SF Symbol。
struct SettingsIconChip: View {
    let systemImage: String
    let tint: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(tint.gradient)
            .frame(width: 26, height: 26)
            .overlay {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}

/// 状态胶囊：着色圆点 + 状态文字 + 可选运行时长。
struct StatusCapsule: View {
    let state: VMRuntimeState
    let startedAt: Date?

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)

            Text(state.title)

            if let startedAt, state == .running || state == .paused {
                Text(startedAt, style: .timer)
                    .monospacedDigit()
            }
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .foregroundStyle(color)
        .background(color.opacity(0.16), in: Capsule())
    }

    private var color: Color {
        switch state {
        case .stopped:
            return .secondary
        case .starting, .stopping:
            return .orange
        case .running:
            return .green
        case .paused:
            return .yellow
        case .failed:
            return .red
        }
    }
}

/// 表单/侧栏/表头共用的应用风格徽标：蓝色渐变圆角方块 + 白色符号。
struct AppMarkChip: View {
    var systemImage = "macwindow"
    var size: CGFloat = 30

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(.blue.gradient)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}
#endif
