enum InterfaceSamplerTests {
    static func all() {
        wifiByInterfaceType()
        iPhoneByDescription()
        otherInterfacesIgnored()
        liveSampleReturnsUniqueInterfaces()
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
}
