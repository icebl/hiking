import Foundation
import CoreLocation

/// KML 解析（导入，原 P1 提前）：
/// 支持 `<LineString><coordinates>`（lon,lat,alt 以空白分隔）、`<gx:Track>`(`<when>`+`<gx:coord>`)，
/// 以及独立 `<Point>` 作为航点。多 Placemark 全部导入。KMZ（压缩）暂不支持。
final class KMLService: NSObject, XMLParserDelegate {

    enum KMLError: Error { case parseFailed, empty }

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
    private var tracks: [(name: String, points: [TrackPoint], hasTime: Bool, hasElevation: Bool)] = []
    private var waypoints: [Waypoint] = []

    private var buffer = ""
    private var folderName: String?            // 文件夹名（作轨迹名兜底，如“赤峰市 徒步”）
    private var inPlacemark = false
    private var placemarkName: String?
    private var inLineString = false
    private var inGxTrack = false
    private var inPoint = false
    private var lineStringCoords = ""               // LineString/Point 的 coordinates 文本
    private var gxCoords: [(lat: Double, lon: Double, ele: Double?)] = []
    private var gxWhens: [Date?] = []
    private var pointCoords = ""

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()

    // MARK: - XMLParserDelegate
    func parser(_ parser: XMLParser, didStartElement el: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes: [String: String]) {
        buffer = ""
        switch el {
        case "Placemark":
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

    func parser(_ parser: XMLParser, didEndElement el: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        let text = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        switch el {
        case "name":
            if inPlacemark { if placemarkName == nil { placemarkName = text } }
            else if folderName == nil { folderName = text }
        case "coordinates":
            if inPoint { pointCoords = text } else if inLineString { lineStringCoords = text }
        case "when":
            if inGxTrack { gxWhens.append(Self.isoFormatter.date(from: text)) }
        case "gx:coord", "coord":
            if inGxTrack {
                let p = text.split(separator: " ").compactMap { Double($0) }
                if p.count >= 2 { gxCoords.append((lat: p[1], lon: p[0], ele: p.count >= 3 ? p[2] : nil)) }
            }
        case "Placemark":
            finalizeCurrentPlacemark()
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

        if !lineStringCoords.isEmpty {
            for tuple in lineStringCoords.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }) {
                let c = tuple.split(separator: ",").compactMap { Double($0) }
                guard c.count >= 2 else { continue }
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
                let t = i < gxWhens.count ? gxWhens[i] : nil
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

        if !pts.isEmpty {
            // 轨迹名：Placemark 名缺失或泛化("Track")时回退用文件夹名
            let generic = placemarkName == nil || placemarkName!.isEmpty || placemarkName!.caseInsensitiveCompare("Track") == .orderedSame
            let name = generic ? (folderName ?? "导入轨迹") : placemarkName!
            tracks.append((name: name, points: pts, hasTime: hasTime, hasElevation: hasEle))
        }
        // 清理，避免重复结算
        lineStringCoords = ""; pointCoords = ""; gxCoords = []; gxWhens = []
    }
}
