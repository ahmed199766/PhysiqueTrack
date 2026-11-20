import Foundation
import UIKit

enum PhotoAngle: String, CaseIterable, Codable, Identifiable {
    case front
    case side
    case back

    var id: String { rawValue }

    var arabicTitle: String {
        switch self {
        case .front: return "أمامي"
        case .side: return "جانبي"
        case .back: return "خلفي"
        }
    }

    var systemImage: String {
        switch self {
        case .front: return "figure.stand"
        case .side: return "figure.walk"
        case .back: return "person.crop.rectangle"
        }
    }
}

struct ProgressEntry: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var date: Date = Date()
    var weightKg: Double
    var bodyFatPercent: Double?
    var notes: String = ""
    /// Maps PhotoAngle.rawValue -> filename inside Documents/ProgressPhotos
    var photoFilenames: [String: String] = [:]

    func filename(for angle: PhotoAngle) -> String? {
        photoFilenames[angle.rawValue]
    }
}

struct BackupPayload: Codable {
    var version: Int = 1
    var exportedAt: Date = Date()
    var entries: [ProgressEntry]
    /// Maps filename -> base64 encoded JPEG data
    var imagesBase64: [String: String]
}

enum AppThemeOption: String, CaseIterable, Identifiable {
    case dark
    case light
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dark: return "داكن"
        case .light: return "فاتح"
        case .system: return "حسب النظام"
        }
    }
}

enum NumberParser {
    static func parseDouble(_ raw: String) -> Double? {
        let arabicDigits: [Character: Character] = [
            "٠": "0", "١": "1", "٢": "2", "٣": "3", "٤": "4",
            "٥": "5", "٦": "6", "٧": "7", "٨": "8", "٩": "9",
            "۰": "0", "۱": "1", "۲": "2", "۳": "3", "۴": "4",
            "۵": "5", "۶": "6", "۷": "7", "۸": "8", "۹": "9",
            "،": ".", ",": ".", "٫": "."
        ]
        let cleaned = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .map { arabicDigits[$0] ?? $0 }
        return Double(String(cleaned))
    }

    static func formatWeight(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    static func formatPercent(_ value: Double) -> String {
        String(format: "%.1f%%", value)
    }
}

extension UIImage {
    func normalizedUp(maxDimension: CGFloat = 1600) -> UIImage {
        let longest = max(size.width, size.height)
        let scaleFactor = longest > maxDimension ? (maxDimension / longest) : 1.0
        let newSize = CGSize(width: size.width * scaleFactor, height: size.height * scaleFactor)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
