enum InterfaceCategory: Hashable {
    case wifi
    case iphone
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
