import Foundation

/// 流量阈值告警：总流量（上行+下行）达到阈值时触发一次
final class TrafficAlert {
    private(set) var threshold: UInt64? // nil = 关闭
    private(set) var fired = false

    init(threshold: UInt64? = nil) {
        self.threshold = threshold
    }

    /// 设置新阈值；换档后重新武装（可再次触发）
    func setThreshold(_ bytes: UInt64?) {
        threshold = bytes
        fired = false
    }

    /// 周期性检查；返回 true 表示本次越线应触发告警。每个阈值只触发一次。
    func check(totalBytes: UInt64) -> Bool {
        guard let threshold, !fired, totalBytes >= threshold else { return false }
        fired = true
        return true
    }

    /// 重置计数时调用：重新武装
    func reset() {
        fired = false
    }
}
