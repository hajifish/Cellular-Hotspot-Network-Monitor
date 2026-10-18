enum ByteFormat {
    private static let units: [(suffix: String, scale: UInt64)] = [
        ("B", 1), ("KB", 1_000), ("MB", 1_000_000), ("GB", 1_000_000_000), ("TB", 1_000_000_000_000),
    ]

    /// "0 B"、"999 B"、"1.0 KB"、"2.5 GB"、"1.2 TB"（十进制单位）；compact 去掉数值与单位间空格
    static func string(_ bytes: UInt64, compact: Bool = false) -> String {
        let unit = units.last { bytes >= $0.scale } ?? units[0]
        guard unit.scale > 1 else { return compact ? "\(bytes)B" : "\(bytes) B" }
        let value = Double(bytes) / Double(unit.scale)
        return compact ? String(format: "%.1f%@", value, unit.suffix)
                       : String(format: "%.1f %@", value, unit.suffix)
    }

    /// 速率显示：在 string 后追加 "/s"
    static func rate(_ bytesPerSecond: UInt64, compact: Bool = false) -> String {
        string(bytesPerSecond, compact: compact) + "/s"
    }

    /// 拆分速率文本为数值与单位（大字号混排用），如 1_200_000 -> ("1.2", "MB/s")
    static func rateParts(_ bytesPerSecond: UInt64) -> (value: String, unit: String) {
        let text = rate(bytesPerSecond)
        guard let space = text.firstIndex(of: " ") else { return (text, "") }
        return (String(text[..<space]), String(text[text.index(after: space)...]))
    }
}
