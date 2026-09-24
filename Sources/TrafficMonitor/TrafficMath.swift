enum TrafficMath {
    /// 计算两个快照之间按类别聚合的字节增量。
    /// - 只统计同时出现在两个快照中的接口（中途插拔的接口不参与当秒统计）
    /// - 负差值（计数器回绕/清零）钳位为 0
    /// - 不在 categories 中的接口忽略
    static func deltas(previous: [String: InterfaceCounters],
                       current: [String: InterfaceCounters],
                       categories: [String: InterfaceCategory]) -> [InterfaceCategory: CategoryDelta] {
        var result: [InterfaceCategory: CategoryDelta] = [:]
        for (name, now) in current {
            guard let category = categories[name], let before = previous[name] else { continue }
            let rx = now.rx > before.rx ? now.rx - before.rx : 0
            let tx = now.tx > before.tx ? now.tx - before.tx : 0
            let existing = result[category] ?? .zero
            result[category] = CategoryDelta(rx: existing.rx + rx, tx: existing.tx + tx)
        }
        return result
    }
}
