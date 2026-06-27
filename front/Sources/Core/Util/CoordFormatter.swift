import Foundation
import CoreLocation

/// 经纬度格式化（任务 2.8）：度 / 度分秒 / UTM，依设置页坐标格式。
enum CoordFormatter {
    /// 按格式名分派；format 取自 AppSettings.coordFormat，无匹配则回落十进制度。
    static func string(_ c: CLLocationCoordinate2D, format: String) -> String {
        switch format {
        case "度分秒 DMS": return dms(c)
        case "UTM":        return utm(c)
        default:           return decimal(c)
        }
    }

    /// 度：41.69500°N 123.34430°E
    static func decimal(_ c: CLLocationCoordinate2D) -> String {
        String(format: "%.5f°%@ %.5f°%@",
               abs(c.latitude), c.latitude >= 0 ? "N" : "S",
               abs(c.longitude), c.longitude >= 0 ? "E" : "W")
    }

    /// 度分秒：41°41'42.0"N 123°20'39.5"E
    static func dms(_ c: CLLocationCoordinate2D) -> String {
        func part(_ v: Double, _ pos: String, _ neg: String) -> String {
            let dir = v >= 0 ? pos : neg
            let a = abs(v)
            let d = Int(a)
            let mFull = (a - Double(d)) * 60
            let m = Int(mFull)
            let s = (mFull - Double(m)) * 60
            return String(format: "%d°%02d'%04.1f\"%@", d, m, s, dir)
        }
        return part(c.latitude, "N", "S") + " " + part(c.longitude, "E", "W")
    }

    /// UTM（WGS84 正算）：50T 423456E 4612345N
    /// 经纬度 → 横轴墨卡托投影坐标。标准公式，含义见各变量注释。
    static func utm(_ c: CLLocationCoordinate2D) -> String {
        let lat = c.latitude, lon = c.longitude
        // a 椭球长半轴(米)，f 扁率；e2 第一偏心率平方，ep2 第二偏心率平方，k0 中央经线比例因子。
        let a = 6378137.0, f = 1 / 298.257223563
        let e2 = f * (2 - f), ep2 = e2 / (1 - e2), k0 = 0.9996
        let zone = min(60, max(1, Int((lon + 180) / 6) + 1))  // 1~60 投影带号，每带 6°
        let lon0 = Double(zone) * 6 - 183                     // 本带中央经线（度）
        let latR = lat * .pi / 180                            // 纬度转弧度
        let dLon = (lon - lon0) * .pi / 180                   // 与中央经线的经差（弧度）
        let N = a / sqrt(1 - e2 * pow(sin(latR), 2))          // 卯酉圈曲率半径
        let T = pow(tan(latR), 2)
        let C = ep2 * pow(cos(latR), 2)
        let A = cos(latR) * dLon
        // M：由赤道到当前纬度的子午线弧长
        let M = a * ((1 - e2/4 - 3*e2*e2/64 - 5*e2*e2*e2/256) * latR
                     - (3*e2/8 + 3*e2*e2/32 + 45*e2*e2*e2/1024) * sin(2*latR)
                     + (15*e2*e2/256 + 45*e2*e2*e2/1024) * sin(4*latR)
                     - (35*e2*e2*e2/3072) * sin(6*latR))
        // 东向坐标：+500000 假东偏移，使带内横坐标恒为正。
        let easting = k0 * N * (A + (1 - T + C) * pow(A, 3) / 6
                     + (5 - 18*T + T*T + 72*C - 58*ep2) * pow(A, 5) / 120) + 500000
        var northing = k0 * (M + N * tan(latR) * (A*A/2
                     + (5 - T + 9*C + 4*C*C) * pow(A, 4) / 24
                     + (61 - 58*T + T*T + 600*C - 330*ep2) * pow(A, 6) / 720))
        if lat < 0 { northing += 10_000_000 }  // 南半球加 1000 万米假北偏移，避免负值
        return String(format: "%d%@ %.0fE %.0fN", zone, band(lat), easting, northing)
    }

    /// 纬度对应的 UTM 纬度带字母（每 8° 一带，从 80°S 起；省略易混的 I/O）。
    private static func band(_ lat: Double) -> String {
        let letters = Array("CDEFGHJKLMNPQRSTUVWX")
        let i = Int((lat + 80) / 8)
        return (i >= 0 && i < letters.count) ? String(letters[i]) : ""
    }
}
