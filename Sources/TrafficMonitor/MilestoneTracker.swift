import Foundation

/// 阈值临近预告：按告警阈值大小自适应的检查点节奏（大阈值临近额度时 20%→10%→5%→1%
/// 逐级预告，小阈值少预告几次），向额度倒计时。100% 不在检查点表内——到阈值那一下
/// 由 TrafficAlert 阈值告警本体负责，预告只做提前量。
struct MilestoneTracker {
    /// 检查点档位表（唯一事实源）：检查点以「已用占阈值的比例」定义，升序。
    /// T ≥ 5GB：80/90/95/99%；1GB ≤ T < 5GB：50/80/95%；T < 1GB：50/90%。
    static func checkpointFractions(forThreshold bytes: UInt64) -> [Double] {
        let gigabyte: UInt64 = 1_000_000_000
        if bytes >= 5 * gigabyte {
            return [0.80, 0.90, 0.95, 0.99]
        }
        if bytes >= gigabyte {
            return [0.50, 0.80, 0.95]
        }
        return [0.50, 0.90]
    }

    /// 阈值对应的检查点字节数：比例 × 阈值四舍五入；
    /// 过滤 0、≥ 阈值及非严格递增者（玩具级小阈值兜底；真实档位间距远大于舍入误差）
    static func checkpoints(forThreshold bytes: UInt64) -> [UInt64] {
        var points: [UInt64] = []
        for fraction in checkpointFractions(forThreshold: bytes) {
            let point = UInt64((Double(bytes) * fraction).rounded())
            guard point > 0, point < bytes, (points.last ?? 0) < point else { continue }
            points.append(point)
        }
        return points
    }

    private var checkpoints: [UInt64] = []
    private var nextIndex = 0
    private var thresholdBytes: UInt64?

    /// 下一个待预告的检查点（字节）；检查点越完或未武装时为 nil
    var next: UInt64? {
        nextIndex < checkpoints.count ? checkpoints[nextIndex] : nil
    }

    /// 武装（设置/恢复阈值、计量重置时调用）：重算检查点并跳过已过者（≤ progressBytes），
    /// 不补发关闭告警或重置前越过的检查点（2026-11-05 既有需求）
    mutating func arm(thresholdBytes: UInt64, progressBytes: UInt64) {
        checkpoints = Self.checkpoints(forThreshold: thresholdBytes)
        self.thresholdBytes = thresholdBytes
        nextIndex = 0
        while nextIndex < checkpoints.count, checkpoints[nextIndex] <= progressBytes {
            nextIndex += 1
        }
    }

    /// 返回本次越过的检查点（字节），无越过则 nil。
    /// 一拍跨多个检查点时只报第一个，后续拍逐个追平（沿用旧语义）；
    /// 进度已到/越过阈值时剩余检查点整体静默收官——倒计时归零，收尾归告警本体，
    /// 不再补发冲线后过期的倒计时预告。
    mutating func update(progressBytes: UInt64) -> UInt64? {
        if let thresholdBytes, progressBytes >= thresholdBytes {
            nextIndex = checkpoints.count
            return nil
        }
        guard nextIndex < checkpoints.count, progressBytes >= checkpoints[nextIndex] else { return nil }
        let reached = checkpoints[nextIndex]
        nextIndex += 1
        return reached
    }
}
