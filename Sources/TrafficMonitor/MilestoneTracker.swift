import Foundation

/// 每 1 GB 里程碑提醒：基于「上次重置以来」的总流量
struct MilestoneTracker {
    static let step: UInt64 = 1_000_000_000

    /// 下一个待提醒的边界（字节）
    private(set) var next: UInt64 = step

    /// 返回本次越过的里程碑（如 1GB、2GB），无越过则返回 nil。
    /// 一拍跨越多个边界时，每拍只报告一个（按序逐拍提醒）。
    mutating func update(totalBytes: UInt64) -> UInt64? {
        guard totalBytes >= next else { return nil }
        let reached = next
        next += Self.step
        return reached
    }

    /// 计量重置后重新对齐：下一个边界 = 当前总量之上的第一个整 GB
    mutating func resync(totalBytes: UInt64) {
        let gb = totalBytes / Self.step
        next = (gb + 1) * Self.step
    }
}
