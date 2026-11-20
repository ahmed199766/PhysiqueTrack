import Foundation
import UIKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class DataStore: ObservableObject {
    @Published private(set) var entries: [ProgressEntry] = []

    private let fileManager = FileManager.default
    private var documentsURL: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    private var entriesFileURL: URL {
        documentsURL.appendingPathComponent("progress_entries.json")
    }
    private var photosDirectoryURL: URL {
        documentsURL.appendingPathComponent("ProgressPhotos", isDirectory: true)
    }

    init() {
        ensurePhotosDirectory()
        loadEntries()
    }

    private func ensurePhotosDirectory() {
        if !fileManager.fileExists(atPath: photosDirectoryURL.path) {
            try? fileManager.createDirectory(at: photosDirectoryURL, withIntermediateDirectories: true)
        }
    }

    func loadEntries() {
        guard let data = try? Data(contentsOf: entriesFileURL) else {
            entries = []
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([ProgressEntry].self, from: data) {
            entries = decoded.sorted { $0.date > $1.date }
        }
    }

    private func persistEntries() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(entries) {
            try? data.write(to: entriesFileURL, options: .atomic)
        }
    }

    // MARK: - Image Storage

    func saveImage(_ image: UIImage) -> String? {
        ensurePhotosDirectory()
        let normalized = image.normalizedUp(maxDimension: 1600)
        guard let jpegData = normalized.jpegData(compressionQuality: 0.82) else { return nil }
        let filename = "\(UUID().uuidString).jpg"
        let url = photosDirectoryURL.appendingPathComponent(filename)
        do {
            try jpegData.write(to: url, options: .atomic)
            return filename
        } catch {
            return nil
        }
    }

    func loadImage(filename: String?) -> UIImage? {
        guard let filename = filename else { return nil }
        let url = photosDirectoryURL.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    func deleteImage(filename: String) {
        let url = photosDirectoryURL.appendingPathComponent(filename)
        try? fileManager.removeItem(at: url)
    }

    // MARK: - Entry CRUD

    func addEntry(
        date: Date,
        weightKg: Double,
        bodyFatPercent: Double?,
        notes: String,
        images: [PhotoAngle: UIImage]
    ) {
        var filenames: [String: String] = [:]
        for (angle, img) in images {
            if let name = saveImage(img) {
                filenames[angle.rawValue] = name
            }
        }
        let entry = ProgressEntry(
            date: date,
            weightKg: weightKg,
            bodyFatPercent: bodyFatPercent,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            photoFilenames: filenames
        )
        entries.append(entry)
        entries.sort { $0.date > $1.date }
        persistEntries()
    }

    func updateEntry(
        _ existing: ProgressEntry,
        date: Date,
        weightKg: Double,
        bodyFatPercent: Double?,
        notes: String,
        updatedImages: [PhotoAngle: UIImage?]
    ) {
        guard let idx = entries.firstIndex(where: { $0.id == existing.id }) else { return }
        var filenames = existing.photoFilenames

        for angle in PhotoAngle.allCases {
            if let maybeImage = updatedImages[angle] {
                if let oldName = filenames[angle.rawValue] {
                    deleteImage(filename: oldName)
                    filenames.removeValue(forKey: angle.rawValue)
                }
                if let newImg = maybeImage, let savedName = saveImage(newImg) {
                    filenames[angle.rawValue] = savedName
                }
            }
        }

        entries[idx].date = date
        entries[idx].weightKg = weightKg
        entries[idx].bodyFatPercent = bodyFatPercent
        entries[idx].notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        entries[idx].photoFilenames = filenames
        entries.sort { $0.date > $1.date }
        persistEntries()
    }

    func deleteEntry(_ entry: ProgressEntry) {
        for filename in entry.photoFilenames.values {
            deleteImage(filename: filename)
        }
        entries.removeAll { $0.id == entry.id }
        persistEntries()
    }

    // MARK: - Helpers & Stats

    func latestPhoto(for angle: PhotoAngle, excluding entryId: UUID? = nil) -> UIImage? {
        for entry in entries {
            if let excluded = entryId, entry.id == excluded { continue }
            if let name = entry.filename(for: angle), let img = loadImage(filename: name) {
                return img
            }
        }
        return nil
    }

    var sortedChronological: [ProgressEntry] {
        entries.sorted { $0.date < $1.date }
    }

    var latestEntry: ProgressEntry? {
        entries.first
    }

    var firstEntry: ProgressEntry? {
        entries.last
    }

    var totalWeightChange: Double? {
        guard let first = firstEntry, let latest = latestEntry, entries.count >= 2 else { return nil }
        return latest.weightKg - first.weightKg
    }

    var totalPhotoCount: Int {
        entries.reduce(0) { $0 + $1.photoFilenames.count }
    }

    // MARK: - Backup & Restore

    func createBackupData() throws -> Data {
        var imagesMap: [String: String] = [:]
        for entry in entries {
            for filename in entry.photoFilenames.values {
                let url = photosDirectoryURL.appendingPathComponent(filename)
                if let data = try? Data(contentsOf: url) {
                    imagesMap[filename] = data.base64EncodedString()
                }
            }
        }
        let payload = BackupPayload(entries: entries, imagesBase64: imagesMap)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(payload)
    }

    func importBackupData(_ data: Data) throws -> Int {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(BackupPayload.self, from: data)
        ensurePhotosDirectory()

        var importedCount = 0
        for var entry in payload.entries {
            if entries.contains(where: { $0.id == entry.id }) {
                continue
            }
            var newFilenames: [String: String] = [:]
            for (angleKey, oldFilename) in entry.photoFilenames {
                if let base64 = payload.imagesBase64[oldFilename],
                   let imgData = Data(base64Encoded: base64) {
                    let targetFilename = "\(UUID().uuidString).jpg"
                    let targetURL = photosDirectoryURL.appendingPathComponent(targetFilename)
                    try imgData.write(to: targetURL, options: .atomic)
                    newFilenames[angleKey] = targetFilename
                }
            }
            entry.photoFilenames = newFilenames
            entries.append(entry)
            importedCount += 1
        }
        entries.sort { $0.date > $1.date }
        persistEntries()
        return importedCount
    }
}

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
