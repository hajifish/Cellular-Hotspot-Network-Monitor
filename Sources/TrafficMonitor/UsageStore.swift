import Foundation
import Observation

/// 单个类别的计量状态：累计收发 + 独立开始时间
struct CategoryUsage: Equatable {
    var rx: UInt64 = 0
    var tx: UInt64 = 0
    var startTime = Date()
}

@Observable
@MainActor
final class UsageStore {
    private(set) var wifi = CategoryUsage()
    private(set) var iphone = CategoryUsage()

    func record(_ deltas: [InterfaceCategory: CategoryDelta]) {
        if let d = deltas[.wifi] {
            wifi.rx += d.rx
            wifi.tx += d.tx
        }
        if let d = deltas[.iphone] {
            iphone.rx += d.rx
            iphone.tx += d.tx
        }
    }

    /// 重置指定类别的累计并重新开始计时；nil = 全部
    func reset(_ category: InterfaceCategory? = nil) {
        if category == nil || category == .wifi { wifi = CategoryUsage() }
        if category == nil || category == .iphone { iphone = CategoryUsage() }
    }

    func usage(for category: InterfaceCategory) -> CategoryUsage {
        category == .wifi ? wifi : iphone
    }

    /// 全部模块中最早的开始时间（会话起点）
    var sessionStart: Date {
        min(wifi.startTime, iphone.startTime)
    }
}
