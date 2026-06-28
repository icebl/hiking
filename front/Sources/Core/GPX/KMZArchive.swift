import Foundation
import Compression

/// KMZ 解包（导入）：KMZ 是含 doc.kml 的 ZIP 包。提取其中的 .kml 写入临时文件，交 KMLService 解析。
/// 不引第三方库：手动读 ZIP 中央目录定位 .kml 条目，用系统 Compression 做 raw-DEFLATE 解压
/// （ZIP method 8 与 Apple COMPRESSION_ZLIB 一致——都是无 zlib 头的裸 deflate 流）。
enum KMZArchive {
    enum KMZError: Error { case notZip, noKML, badEntry }

    /// 从 .kmz 提取出 .kml，返回临时 .kml 文件 URL。
    static func extractKML(from url: URL) throws -> URL {
        let data = try Data(contentsOf: url)
        guard let kml = try firstKMLData(in: data) else { throw KMZError.noKML }
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("kmz-\(UUID().uuidString).kml")
        try kml.write(to: out)
        return out
    }

    /// 在 ZIP 数据中找到第一个 .kml 条目（优先 doc.kml）并返回其解压后的字节。
    private static func firstKMLData(in data: Data) throws -> Data? {
        let b = [UInt8](data)
        // 1) 尾部回扫 EOCD（End of Central Directory，签名 0x06054b50）
        guard let eocd = findEOCD(b) else { throw KMZError.notZip }
        let cdCount = Int(u16(b, eocd + 10))
        var p = Int(u32(b, eocd + 16))          // 中央目录起始偏移

        // 2) 遍历中央目录条目，挑 .kml
        var pick: (offset: Int, method: Int, compSize: Int, uncompSize: Int)?
        for _ in 0..<cdCount {
            guard p + 46 <= b.count, u32(b, p) == 0x02014b50 else { break }   // 中央目录头签名
            let method = Int(u16(b, p + 10))
            let compSize = Int(u32(b, p + 20))
            let uncompSize = Int(u32(b, p + 24))
            let nameLen = Int(u16(b, p + 28))
            let extraLen = Int(u16(b, p + 30))
            let commentLen = Int(u16(b, p + 32))
            let localOffset = Int(u32(b, p + 42))
            guard p + 46 + nameLen <= b.count else { break }
            let name = String(bytes: b[(p + 46)..<(p + 46 + nameLen)], encoding: .utf8) ?? ""
            if name.lowercased().hasSuffix(".kml") {
                let entry = (localOffset, method, compSize, uncompSize)
                if name.lowercased().hasSuffix("doc.kml") { pick = entry; break }   // 首选 doc.kml
                if pick == nil { pick = entry }
            }
            p += 46 + nameLen + extraLen + commentLen
        }
        guard let e = pick else { return nil }

        // 3) 定位本地文件头（签名 0x04034b50）。数据起点 = 头(30)+名长+扩展长
        //    注意：本地头的扩展长可能与中央目录不同，必须用本地头里的值。
        let lo = e.offset
        guard lo + 30 <= b.count, u32(b, lo) == 0x04034b50 else { throw KMZError.badEntry }
        let nameLen = Int(u16(b, lo + 26))
        let extraLen = Int(u16(b, lo + 28))
        let dataStart = lo + 30 + nameLen + extraLen
        guard dataStart + e.compSize <= b.count else { throw KMZError.badEntry }
        let comp = data.subdata(in: dataStart..<(dataStart + e.compSize))

        // 4) 解压：0=存储(直接用)，8=DEFLATE
        switch e.method {
        case 0: return comp
        case 8: return inflate(comp, expected: e.uncompSize)
        default: throw KMZError.badEntry
        }
    }

    /// 尾部回扫 EOCD 签名（允许 ZIP 末尾有注释，最多回看注释上限 0xFFFF + 22 字节）。
    private static func findEOCD(_ b: [UInt8]) -> Int? {
        let minLen = 22
        guard b.count >= minLen else { return nil }
        let lowerBound = max(0, b.count - (minLen + 0xFFFF))
        var i = b.count - minLen
        while i >= lowerBound {
            if u32(b, i) == 0x06054b50 { return i }
            i -= 1
        }
        return nil
    }

    /// raw DEFLATE 解压到 expected 字节。
    private static func inflate(_ comp: Data, expected: Int) -> Data? {
        guard expected > 0 else { return Data() }
        var out = Data(count: expected)
        let n = out.withUnsafeMutableBytes { dst -> Int in
            comp.withUnsafeBytes { src in
                compression_decode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, expected,
                                          src.bindMemory(to: UInt8.self).baseAddress!, comp.count,
                                          nil, COMPRESSION_ZLIB)
            }
        }
        guard n > 0 else { return nil }
        return n == expected ? out : out.prefix(n)
    }

    // 小端读取（调用前已保证下标在界内）
    private static func u16(_ b: [UInt8], _ i: Int) -> UInt16 { UInt16(b[i]) | (UInt16(b[i + 1]) << 8) }
    private static func u32(_ b: [UInt8], _ i: Int) -> UInt32 {
        UInt32(b[i]) | (UInt32(b[i + 1]) << 8) | (UInt32(b[i + 2]) << 16) | (UInt32(b[i + 3]) << 24)
    }
}
