import Testing
@testable import TrafficMonitor

struct TrafficMathTests {
    private func c(_ rx: UInt64, _ tx: UInt64) -> InterfaceCounters {
        InterfaceCounters(rx: rx, tx: tx)
    }

    @Test func normalDelta() {
        let d = TrafficMath.deltas(
            previous: ["en0": c(100, 50)],
            current: ["en0": c(160, 80)],
            categories: ["en0": .wifi])
        #expect(d[.wifi] == CategoryDelta(rx: 60, tx: 30))
    }

    @Test func negativeDeltaClampedToZero() {
        // iPhone 拔插后计数器清零的场景
        let d = TrafficMath.deltas(
            previous: ["en5": c(10_000, 5_000)],
            current: ["en5": c(300, 100)],
            categories: ["en5": .iphone])
        #expect(d[.iphone] == CategoryDelta.zero)
    }

    @Test func newInterfaceContributesNothing() {
        // 刚插入的接口没有上一拍基线：不产生该类别的条目（即不计入任何增量）
        let d = TrafficMath.deltas(
            previous: [:],
            current: ["en5": c(987_654_321, 123_456_789)],
            categories: ["en5": .iphone])
        #expect(d[.iphone] == nil)
    }

    @Test func uncategorizedInterfacesIgnored() {
        let d = TrafficMath.deltas(
            previous: ["utun3": c(1, 1), "en0": c(10, 10)],
            current: ["utun3": c(500, 500), "en0": c(20, 15)],
            categories: ["en0": .wifi])
        #expect(d == [.wifi: CategoryDelta(rx: 10, tx: 5)])
    }

    @Test func sameCategorySumsAcrossInterfaces() {
        let d = TrafficMath.deltas(
            previous: ["en0": c(0, 0), "en1": c(0, 0)],
            current: ["en0": c(30, 0), "en1": c(0, 40)],
            categories: ["en0": .wifi, "en1": .wifi])
        #expect(d[.wifi] == CategoryDelta(rx: 30, tx: 40))
    }

    @Test func disappearedInterfaceExcluded() {
        let d = TrafficMath.deltas(
            previous: ["en5": c(1000, 1000), "en0": c(10, 10)],
            current: ["en0": c(20, 20)],
            categories: ["en5": .iphone, "en0": .wifi])
        #expect(d[.iphone] == nil)
        #expect(d[.wifi] == CategoryDelta(rx: 10, tx: 10))
    }
}
