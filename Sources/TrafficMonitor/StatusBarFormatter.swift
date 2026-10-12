import Foundation

/// 状态栏显示模式
enum MenuBarDisplayMode: String, CaseIterable {
    case ratesOnly
    case totalsOnly
    case both
    case iconOnly

    var label: String {
        switch self {
        case .ratesOnly: return "只显示实时速率"
        case .totalsOnly: return "只显示累计流量"
        case .both: return "速率 + 累计"
        case .iconOnly: return "只显示图标"
        }
    }
}

enum StatusBarFormatter {
    /// 状态栏文字；iconOnly 返回 nil（只显示图标）
    static func text(for mode: MenuBarDisplayMode, totalRate: CategoryDelta,
                     totalRX: UInt64, totalTX: UInt64) -> String? {
        switch mode {
        case .iconOnly:
            return nil
        case .ratesOnly:
            return "↑\(ByteFormat.rate(totalRate.tx)) ↓\(ByteFormat.rate(totalRate.rx))"
        case .totalsOnly:
            return "↑\(ByteFormat.string(totalTX)) ↓\(ByteFormat.string(totalRX))"
        case .both:
            return "↑\(ByteFormat.string(totalTX)) (\(ByteFormat.rate(totalRate.tx)))"
                + " ↓\(ByteFormat.string(totalRX)) (\(ByteFormat.rate(totalRate.rx)))"
        }
    }
}
