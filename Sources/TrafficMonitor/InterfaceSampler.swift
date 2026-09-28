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

    /// 通过 sysctl(NET_RT_IFLIST2) 读取 64 位字节计数。
    /// 注意：getifaddrs 的 ifa_data 是 32 位 if_data（会回绕且偏移不匹配），
    /// netstat -ib 的 64 位大计数与本方法同源。
    func sample() -> [ClassifiedSample] {
        let categories = categoryByBSDName
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length: size_t = 0
        guard sysctl(&mib, 6, nil, &length, nil, 0) == 0, length > 0 else { return [] }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, 6, &buffer, &length, nil, 0) == 0 else { return [] }

        var result: [ClassifiedSample] = []
        buffer.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset + MemoryLayout<if_msghdr2>.size <= length {
                let message = base.advanced(by: offset).assumingMemoryBound(to: if_msghdr2.self).pointee
                let messageLength = Int(message.ifm_msglen)
                guard messageLength > 0, offset + messageLength <= length else { break }
                if message.ifm_type == RTM_IFINFO2, Int(message.ifm_addrs) & Int(RTA_IFP) != 0 {
                    // sockaddr_dl 跟在 if_msghdr2 固定部分之后
                    let name = Self.interfaceName(at: base.advanced(by: offset + MemoryLayout<if_msghdr2>.size))
                    if let name {
                        result.append(ClassifiedSample(
                            name: name,
                            category: categories[name],
                            counters: InterfaceCounters(rx: message.ifm_data.ifi_ibytes,
                                                        tx: message.ifm_data.ifi_obytes)))
                    }
                }
                offset += (messageLength + 3) & ~3 // 路由消息 4 字节对齐
            }
        }
        return result
    }

    /// 指针指向 sockaddr_dl（紧跟 if_msghdr2 固定部分），接口名在 sdl_data 前 sdl_nlen 字节
    private static func interfaceName(at message: UnsafeMutableRawPointer) -> String? {
        let sdl = message.assumingMemoryBound(to: sockaddr_dl.self).pointee
        let nameLength = Int(sdl.sdl_nlen)
        guard nameLength > 0, nameLength <= 12 else { return nil }
        var name = ""
        withUnsafeBytes(of: sdl.sdl_data) { raw in
            name = String(decoding: raw.prefix(nameLength), as: UTF8.self)
        }
        return name
    }
}
