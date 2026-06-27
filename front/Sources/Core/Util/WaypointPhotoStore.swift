import UIKit

/// 航点照片存储（拍照打点）：照片按航点 id 存到 Documents/waypoint-photos/<id>.jpg。
/// 用「文件是否存在」表示该航点有无照片，省去数据库字段与迁移。
enum WaypointPhotoStore {

    /// 存储目录（Documents 下，属用户内容、不被系统回收）；首次访问创建。
    private static let dir: URL = {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("waypoint-photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    /// 某航点照片的文件路径（无论是否存在）。
    static func url(_ id: UUID) -> URL { dir.appendingPathComponent("\(id.uuidString).jpg") }

    /// 该航点是否有照片。
    static func exists(_ id: UUID) -> Bool { FileManager.default.fileExists(atPath: url(id).path) }

    /// 保存照片：先按最长边 1600px 压缩再以 JPEG(0.8) 落盘，控制体积。返回是否成功。
    @discardableResult
    static func save(_ image: UIImage, id: UUID) -> Bool {
        guard let data = downscale(image, maxEdge: 1600).jpegData(compressionQuality: 0.8) else { return false }
        do { try data.write(to: url(id)); return true } catch { return false }
    }

    /// 读取照片（不存在返回 nil）。
    static func load(_ id: UUID) -> UIImage? { UIImage(contentsOfFile: url(id).path) }

    /// 删除照片（删除航点时一并清理）。
    static func delete(_ id: UUID) { try? FileManager.default.removeItem(at: url(id)) }

    /// 等比缩小到最长边不超过 maxEdge；本就够小则原样返回。
    private static func downscale(_ image: UIImage, maxEdge: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxEdge else { return image }
        let scale = maxEdge / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
