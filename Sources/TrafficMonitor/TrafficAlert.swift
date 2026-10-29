import Foundation

/// 流量阈值告警：以设置时刻的总流量为基线，进度从零起算，达到阈值时触发一次
final class TrafficAlert {
    private(set) var threshold: UInt64? // nil = 关闭
    private(set) var fired = false
    /// 告警起算基线：进度 = 当前总流量 − 基线（设置/重置告警时更新）
    private(set) var baselineBytes: UInt64 = 0

    init(threshold: UInt64? = nil, baselineBytes: UInt64 = 0) {
        self.threshold = threshold
        self.baselineBytes = baselineBytes
    }

    /// 设置新阈值，并从当前总流量重新起算（旧的累计不纳入进度）
    func setThreshold(_ bytes: UInt64?, baselineBytes: UInt64 = 0) {
        threshold = bytes
        self.baselineBytes = baselineBytes
        fired = false
    }

    /// 告警进度（字节）：当前总流量超出基线的部分
    func progress(totalBytes: UInt64) -> UInt64 {
        totalBytes > baselineBytes ? totalBytes - baselineBytes : 0
    }

    /// 周期性检查；返回 true 表示本次越线应触发告警。每个阈值只触发一次。
    func check(totalBytes: UInt64) -> Bool {
        guard let threshold, !fired, progress(totalBytes: totalBytes) >= threshold else { return false }
        fired = true
        return true
    }

    /// 重置计量时把基线挪到当前总量：进度清零并重新武装
    func reset(baselineBytes: UInt64) {
        self.baselineBytes = baselineBytes
        fired = false
    }
}
