import Foundation
import CoreLocation

/// KML 解析（导入，原 P1 提前）：
/// 支持 `<LineString><coordinates>`（lon,lat,alt 以空白分隔）、`<gx:Track>`(`<when>`+`<gx:coord>`)，
/// 以及独立 `<Point>` 作为航点。多 Placemark 全部导入。KMZ（压缩）暂不支持。
final class KMLService: NSObject, XMLParserDelegate {

    // parseFailed：XML 无法读取/解析；empty：无任何线轨迹也无航点
    enum KMLError: Error { case parseFailed, empty }

    /// 解析 KML 文件 → ParsedTrack 列表。基于 SAX 流式回调（见下方 XMLParserDelegate）。
    func parse(url: URL) throws -> [GPXService.ParsedTrack] {
        guard let parser = XMLParser(contentsOf: url) else { throw KMLError.parseFailed }
        parser.shouldProcessNamespaces = false   // 保留 gx: 前缀，按原始 elementName 匹配
        parser.delegate = self
        guard parser.parse() else { throw KMLError.parseFailed }

        finalizeCurrentPlacemark()   // 收尾最后一个

        var result: [GPXService.ParsedTrack] = []
        for t in tracks where !t.points.isEmpty {
            result.append(GPXService.ParsedTrack(name: t.name, points: t.points,
                                                 waypoints: waypoints, hasTime: t.hasTime,
                                                 hasElevation: t.hasElevation))
        }
        // 若没有线轨迹但有航点，仍返回空轨迹列表交由上层判断
        if result.isEmpty && waypoints.isEmpty { throw KMLError.empty }
        if result.isEmpty {
            // 仅航点：挂到一条空壳轨迹上，避免丢失
            result.append(GPXService.ParsedTrack(name: "导入航点", points: [],
                                                 waypoints: waypoints, hasTime: false, hasElevation: false))
        }
        return result
    }

    // MARK: - 解析状态
    // SAX 解析是有状态的：下列字段在回调间累积，每个 Placemark 结束时结算一次。
    private var tracks: [(name: String, points: [TrackPoint], hasTime: Bool, hasElevation: Bool)] = []
    private var waypoints: [Waypoint] = []

    private var buffer = ""                     // 当前元素的字符内容累积（含 CDATA）
    private var folderName: String?            // 文件夹名（作轨迹名兜底，如“赤峰市 徒步”）
    private var inPlacemark = false            // 以下 in* 为当前所处元素的开关标记
    private var placemarkName: String?
    private var inLineString = false
    private var inGxTrack = false
    private var inPoint = false
    private var lineStringCoords = ""               // LineString/Point 的 coordinates 文本
    private var gxCoords: [(lat: Double, lon: Double, ele: Double?)] = []   // gx:Track 的坐标序列
    private var gxWhens: [Date?] = []                                        // gx:Track 的时间序列（与 gxCoords 按下标对齐）
    private var pointCoords = ""

    // gx:Track 的 <when> 时间为 ISO8601，复用同一格式器避免重复创建
    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()

    // MARK: - XMLParserDelegate
    // 元素开始：重置字符缓冲，并按标签置位对应状态开关
    func parser(_ parser: XMLParser, didStartElement el: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes: [String: String]) {
        buffer = ""
        switch el {
        case "Placemark":
            // 进入新 Placemark：清空上一个的残留状态，避免串数据
            inPlacemark = true; placemarkName = nil
            inLineString = false; inGxTrack = false; inPoint = false
            lineStringCoords = ""; pointCoords = ""
            gxCoords = []; gxWhens = []
        case "LineString": inLineString = true
        case "gx:Track", "Track": inGxTrack = true
        case "Point": inPoint = true
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        buffer += string
    }

    /// 名称等常以 CDATA 包裹（如两步路导出 `<name><![CDATA[…]]></name>`），
    /// CDATA 内容只走此回调、不走 foundCharacters，必须并入 buffer 否则名字丢失。
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let s = String(data: CDATABlock, encoding: .utf8) { buffer += s }
    }

    // 元素结束：buffer 此时已含完整文本，按标签归档到对应字段
    func parser(_ parser: XMLParser, didEndElement el: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        let text = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        switch el {
        case "name":
            // Placemark 内的 name 作轨迹/航点名；外层 name 作文件夹兜底名
            if inPlacemark { if placemarkName == nil { placemarkName = text } }
            else if folderName == nil { folderName = text }
        case "coordinates":
            // KML 坐标顺序为 lon,lat,alt，与常见 lat,lon 相反
            if inPoint { pointCoords = text } else if inLineString { lineStringCoords = text }
        case "when":
            if inGxTrack { gxWhens.append(Self.isoFormatter.date(from: text)) }   // 解析失败存 nil，保持与 coord 下标对齐
        case "gx:coord", "coord":
            if inGxTrack {
                let p = text.split(separator: " ").compactMap { Double($0) }
                if p.count >= 2 { gxCoords.append((lat: p[1], lon: p[0], ele: p.count >= 3 ? p[2] : nil)) }   // 注意 p[1]=lat、p[0]=lon
            }
        case "Placemark":
            finalizeCurrentPlacemark()   // 收尾本 Placemark
            inPlacemark = false
        default: break
        }
        buffer = ""
    }

    /// 结算当前 Placemark：按收集到的内容判定线轨迹或航点。
    private func finalizeCurrentPlacemark() {
        guard inPlacemark else { return }
        var pts: [TrackPoint] = []
        var hasTime = false, hasEle = false
        var seq = 0

        // 三选一优先级：LineString（普通路线） > gx:Track（含时间轨迹） > Point（单点航点）
        if !lineStringCoords.isEmpty {
            // 坐标组以空白分隔，组内 lon,lat[,alt] 以逗号分隔
            for tuple in lineStringCoords.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }) {
                let c = tuple.split(separator: ",").compactMap { Double($0) }
                guard c.count >= 2 else { continue }   // 不足经纬度则跳过
                let ele: Double? = c.count >= 3 ? c[2] : nil
                if ele != nil { hasEle = true }
                pts.append(TrackPoint(id: nil, trackId: UUID(), segment: 0, seq: seq,
                                      lat: c[1], lon: c[0], elevation: ele, timestamp: nil,
                                      speed: nil, horizontalAccuracy: nil))
                seq += 1
            }
        } else if !gxCoords.isEmpty {
            for (i, c) in gxCoords.enumerated() {
                if c.ele != nil { hasEle = true }
                let t = i < gxWhens.count ? gxWhens[i] : nil   // 时间按下标与坐标对齐，缺失则无时间
                if t != nil { hasTime = true }
                pts.append(TrackPoint(id: nil, trackId: UUID(), segment: 0, seq: seq,
                                      lat: c.lat, lon: c.lon, elevation: c.ele, timestamp: t,
                                      speed: nil, horizontalAccuracy: nil))
                seq += 1
            }
        } else if !pointCoords.isEmpty {
            // 航点单组坐标：兼容逗号分隔(标准)与空格分隔(COROS 等导出)
            let c = pointCoords
                .split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\n" || $0 == "\t" })
                .compactMap { Double($0) }
            if c.count >= 2 {
                waypoints.append(Waypoint(id: UUID(), trackId: nil, name: placemarkName ?? "航点",
                                          kind: .other, lat: c[1], lon: c[0],
                                          elevation: c.count >= 3 ? c[2] : nil, note: nil,
                                          createdAt: Date(), updatedAt: Date(),
                                          isDeleted: false, isSynced: false))
            }
        }

        if !pts.isEmpty {   // 有线轨迹点才记为一条轨迹；纯航点不进 tracks
            // 轨迹名：Placemark 名缺失或泛化("Track")时回退用文件夹名
            let generic = placemarkName == nil || placemarkName!.isEmpty || placemarkName!.caseInsensitiveCompare("Track") == .orderedSame
            let name = generic ? (folderName ?? "导入轨迹") : placemarkName!
            tracks.append((name: name, points: pts, hasTime: hasTime, hasElevation: hasEle))
        }
        // 清理，避免重复结算
        lineStringCoords = ""; pointCoords = ""; gxCoords = []; gxWhens = []
    }

    // MARK: - 导出（KML 2.2）
    /// 导出为 KML：轨迹作单条 `<LineString>`，航点各作 `<Point>` Placemark → 临时文件 URL，交系统分享。
    /// 说明：KML 无标准航点类型字段，故 kind 仅写入 `<description>` 供人读，导入回来不还原 kind（GPX 才保留）。
    /// - Parameters: track 轨迹元信息（取名称）；points 轨迹点；waypoints 航点。
    static func export(track: Track, points: [TrackPoint], waypoints: [Waypoint]) throws -> URL {
        // XML 文本转义：& < > 必须转义，否则名称含这些字符会破坏 XML
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;")
             .replacingOccurrences(of: "<", with: "&lt;")
             .replacingOccurrences(of: ">", with: "&gt;")
        }
        // KML 坐标顺序为 lon,lat[,alt]（与常见 lat,lon 相反）；无海拔则省略第三位
        func coord(_ lat: Double, _ lon: Double, _ ele: Double?) -> String {
            ele.map { "\(lon),\(lat),\($0)" } ?? "\(lon),\(lat)"
        }

        // 轨迹点按 段→序 排序后拼成一条 LineString（KML 单线不分段）
        let ordered = points.sorted { $0.segment != $1.segment ? $0.segment < $1.segment : $0.seq < $1.seq }
        let lineCoords = ordered.map { coord($0.lat, $0.lon, $0.elevation) }.joined(separator: " ")

        var kml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <kml xmlns="http://www.opengis.net/kml/2.2">
        <Document>
        <name>\(esc(track.name))</name>
        <Placemark>
        <name>\(esc(track.name))</name>
        <LineString><tessellate>1</tessellate><coordinates>\(lineCoords)</coordinates></LineString>
        </Placemark>
        """
        // 航点：每个一个 Point Placemark，类型与备注写进 description
        for w in waypoints {
            let desc = esc(w.kind.label) + (w.note.map { "：" + esc($0) } ?? "")
            kml += "\n<Placemark><name>\(esc(w.name))</name><description>\(desc)</description>"
                + "<Point><coordinates>\(coord(w.lat, w.lon, w.elevation))</coordinates></Point></Placemark>"
        }
        kml += "\n</Document>\n</kml>\n"

        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("\(track.name).kml")
        try kml.write(to: tmp, atomically: true, encoding: .utf8)
        return tmp   // 交给系统分享面板
    }
}
