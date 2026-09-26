import Darwin
import SystemConfiguration

protocol InterfaceSampling {
    /// 采样一次所有链路层接口；category 为 nil 表示与本应用无关
    func sample() -> [ClassifiedSample]
}

enum InterfaceClassifier {
    /// 纯分类规则：Wi-Fi 按接口类型，iPhone USB 按本地化描述
    static func category(interfaceType: String, description: String) -> InterfaceCategory? {
        if interfaceType == kSCNetworkInterfaceTypeIEEE80211 as String { return .wifi }
        if description.localizedCaseInsensitiveContains("iPhone") { return .iphone }
        return nil
    }
}

struct InterfaceSampler: InterfaceSampling {
    private var categoryByBSDName: [String: InterfaceCategory] {
        var result: [String: InterfaceCategory] = [:]
        guard let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else { return result }
        for iface in interfaces {
            guard let bsd = SCNetworkInterfaceGetBSDName(iface) as String? else { continue }
            let type = SCNetworkInterfaceGetInterfaceType(iface) as String? ?? ""
            let description = SCNetworkInterfaceGetLocalizedDisplayName(iface) as String? ?? ""
            if let category = InterfaceClassifier.category(interfaceType: type, description: description) {
                result[bsd] = category
            }
        }
        return result
    }

    func sample() -> [ClassifiedSample] {
        let categories = categoryByBSDName
        var result: [ClassifiedSample] = []
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let first = ifaddrPtr else { return result }
        defer { freeifaddrs(ifaddrPtr) }

        var seen = Set<String>()
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let ptr = cursor {
            let ifa = ptr.pointee
            cursor = ifa.ifa_next
            guard let sa = ifa.ifa_addr, sa.pointee.sa_family == UInt8(AF_LINK) else { continue }
            let name = String(cString: ifa.ifa_name)
            guard seen.insert(name).inserted else { continue } // 每个接口取第一条 AF_LINK 记录
            var rx: UInt64 = 0
            var tx: UInt64 = 0
            if let dataPtr = ifa.ifa_data {
                // macOS 的 getifaddrs 在 ifa_data 里放的是 64 位 if_data64
                // （netstat -ib 的大计数同源；32 位 if_data 会在 4GB 回绕）
                let data = dataPtr.assumingMemoryBound(to: if_data64.self).pointee
                rx = data.ifi_ibytes
                tx = data.ifi_obytes
            }
            result.append(ClassifiedSample(name: name,
                                           category: categories[name],
                                           counters: InterfaceCounters(rx: rx, tx: tx)))
        }
        return result
    }
}
