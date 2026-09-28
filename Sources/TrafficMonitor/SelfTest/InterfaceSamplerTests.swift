import Foundation

enum InterfaceSamplerTests {
    static func all() {
        wifiByInterfaceType()
        iPhoneByDescription()
        otherInterfacesIgnored()
        liveSampleReturnsUniqueInterfaces()
        liveCountersMoveWithPing()
    }

    static func wifiByInterfaceType() {
        TestRun.expectEqual(InterfaceClassifier.category(interfaceType: "IEEE80211", description: "Wi-Fi"), .wifi, "wifi by type")
    }

    static func iPhoneByDescription() {
        TestRun.expectEqual(InterfaceClassifier.category(interfaceType: "Ethernet", description: "iPhone USB"), .iphone, "iPhone USB")
        TestRun.expectEqual(InterfaceClassifier.category(interfaceType: "Ethernet", description: "iphone"), .iphone, "case insensitive")
    }

    static func otherInterfacesIgnored() {
        TestRun.expect(InterfaceClassifier.category(interfaceType: "Ethernet", description: "USB 10/100/1000 LAN") == nil, "usb lan ignored")
        TestRun.expect(InterfaceClassifier.category(interfaceType: "Ethernet", description: "Ethernet") == nil, "ethernet ignored")
        TestRun.expect(InterfaceClassifier.category(interfaceType: "", description: "") == nil, "empty ignored")
    }

    /// 集成冒烟测试：真实系统上至少采到一个接口，且名字唯一
    static func liveSampleReturnsUniqueInterfaces() {
        let samples = InterfaceSampler().sample()
        TestRun.expect(!samples.isEmpty, "live sample non-empty")
        let names = samples.map(\.name)
        TestRun.expectEqual(names.count, Set(names).count, "unique names")
    }

    /// 集成测试：ping 通默认网关后，被分类接口的累计字节必须增长。
    /// 防止"读到了计数器但读的不是真实字节数"这类 bug 回归。
    /// 若默认路由接口不在被分类之列（环境不符）或 ping 不通，则跳过断言。
    static func liveCountersMoveWithPing() {
        guard let gateway = Self.defaultGatewayInfo() else { return }
        let sampler = InterfaceSampler()
        let total: ([ClassifiedSample]) -> UInt64 = { samples in
            samples.reduce(0) { $0 + $1.counters.rx + $1.counters.tx }
        }
        // 默认路由接口必须在被分类之列，否则 ping 流量不会计入任何分类
        let samples = sampler.sample()
        guard samples.contains(where: { $0.name == gateway.interface && $0.category != nil })
        else { return }

        let before = total(samples)
        let ping = Process()
        ping.executableURL = URL(fileURLWithPath: "/sbin/ping")
        ping.arguments = ["-c", "10", "-i", "0.1", gateway.address]
        try? ping.run()
        ping.waitUntilExit()
        guard ping.terminationStatus == 0 else { return } // ping 不通的环境跳过
        Thread.sleep(forTimeInterval: 1.2) // 等下一次采样窗口把增量吃进来
        let after = total(sampler.sample())
        TestRun.expect(after > before, "counters grew after ping: \(before) -> \(after)")
    }

    static func defaultGatewayInfo() -> (address: String, interface: String)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/route")
        process.arguments = ["-n", "get", "default"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let text = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
        else { return nil }
        var address: String?
        var interface: String?
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: " ").filter { !$0.isEmpty }
            if parts.first == "gateway:", let last = parts.last { address = String(last) }
            if parts.first == "interface:", let last = parts.last { interface = String(last) }
        }
        guard let a = address, let i = interface else { return nil }
        return (a, i)
    }
}
