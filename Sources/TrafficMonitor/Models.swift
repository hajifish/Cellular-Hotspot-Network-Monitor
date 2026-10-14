enum InterfaceCategory: Hashable {
    case wifi
    case iphone

    /// 用户可见名称（菜单与主页共用）
    var displayName: String {
        self == .wifi ? "Wi-Fi" : "iPhone"
    }
}

struct InterfaceCounters: Equatable {
    var rx: UInt64
    var tx: UInt64
}

struct CategoryDelta: Equatable {
    var rx: UInt64
    var tx: UInt64

    static let zero = CategoryDelta(rx: 0, tx: 0)
}

struct ClassifiedSample {
    let name: String
    let category: InterfaceCategory?
    let counters: InterfaceCounters
}
