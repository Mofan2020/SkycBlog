import Foundation
import ImageIO

/// 使用 ImageIO 读取 JPEG/HEIC/TIFF 的 EXIF 元数据。
public enum EXIFReader {
    public struct Info {
        public var make: String?
        public var model: String?
        public var lens: String?
        public var dateTimeOriginal: Date?
        public var pixelX: Int?
        public var pixelY: Int?
        public var iso: Int?
        public var aperture: Double?
        public var shutter: String?
        public var focalLength: Double?
        public var latitude: Double?
        public var longitude: Double?
        public var altitude: Double?
        public var all: [String: String] = [:]
    }

    public static func read(at path: String) -> Info {
        var info = Info()
        guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any] else {
            return info
        }
        info.pixelX = props[kCGImagePropertyPixelWidth as String] as? Int
        info.pixelY = props[kCGImagePropertyPixelHeight as String] as? Int
        if let exif = props[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            info.make = exif[kCGImagePropertyExifLensMake as String] as? String
            info.model = exif[kCGImagePropertyExifLensModel as String] as? String
            info.lens = exif[kCGImagePropertyExifLensModel as String] as? String
            info.iso = (exif[kCGImagePropertyExifISOSpeedRatings as String] as? [Int])?.first
            info.aperture = exif[kCGImagePropertyExifFNumber as String] as? Double
            info.focalLength = exif[kCGImagePropertyExifFocalLength as String] as? Double
            if let exp = exif[kCGImagePropertyExifExposureTime as String] as? Double {
                info.shutter = exp >= 1 ? "\(Int(exp))s" : "1/\(Int(1.0/exp))s"
            }
            if let dt = exif[kCGImagePropertyExifDateTimeOriginal as String] as? String {
                let df = DateFormatter()
                df.dateFormat = "yyyy:MM:dd HH:mm:ss"
                info.dateTimeOriginal = df.date(from: dt)
            }
            for (k, v) in exif {
                if let s = v as? String { info.all[k] = s }
            }
        }
        if let tiff = props[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
            if info.make == nil { info.make = tiff[kCGImagePropertyTIFFMake as String] as? String }
            if info.model == nil { info.model = tiff[kCGImagePropertyTIFFModel as String] as? String }
        }
        if let gps = props[kCGImagePropertyGPSDictionary as String] as? [String: Any] {
            if let lat = gps[kCGImagePropertyGPSLatitude as String] as? Double,
               let latR = gps[kCGImagePropertyGPSLatitudeRef as String] as? String {
                info.latitude = (latR == "S") ? -lat : lat
            }
            if let lon = gps[kCGImagePropertyGPSLongitude as String] as? Double,
               let lonR = gps[kCGImagePropertyGPSLongitudeRef as String] as? String {
                info.longitude = (lonR == "W") ? -lon : lon
            }
            info.altitude = gps[kCGImagePropertyGPSAltitude as String] as? Double
        }
        return info
    }

    public static func dmsToDecimal(_ dms: Double) -> Double { return dms }

    public static func summarize(_ info: Info) -> String {
        var parts: [String] = []
        if let make = info.make, !make.isEmpty { parts.append(make) }
        if let model = info.model, !model.isEmpty { parts.append(model) }
        if let lens = info.lens, !lens.isEmpty { parts.append(lens) }
        if let f = info.aperture { parts.append("f/\(f)") }
        if let s = info.shutter { parts.append(s) }
        if let iso = info.iso { parts.append("ISO \(iso)") }
        if let fl = info.focalLength { parts.append("\(Int(fl))mm") }
        return parts.joined(separator: " · ")
    }
}
