import Foundation

struct RateSample: Equatable {
    var rx: UInt64
    var tx: UInt64
}

/// 滚动速率历史：每秒一条增量，保留最近 capacity 条
final class RateHistory {
    let capacity: Int
    private(set) var samples: [RateSample] = []

    init(capacity: Int = 120) {
        precondition(capacity > 0)
        self.capacity = capacity
    }

    func push(_ sample: RateSample) {
        samples.append(sample)
        if samples.count > capacity {
            samples.removeFirst(samples.count - capacity)
        }
    }

    func clear() {
        samples.removeAll()
    }

    /// 最近 window 秒的平均速率（B/s）；样本数不足 window 时按实际条数平均
    func averageRX(window: Int) -> UInt64 { average({ $0.rx }, window: window) }
    func averageTX(window: Int) -> UInt64 { average({ $0.tx }, window: window) }

    private func average(_ field: (RateSample) -> UInt64, window: Int) -> UInt64 {
        let recent = samples.suffix(max(1, window))
        guard !recent.isEmpty else { return 0 }
        return recent.reduce(UInt64(0)) { $0 + field($1) } / UInt64(recent.count)
    }
}
