import SwiftUI
import PhotosUI

struct AddEditEntryView: View {
    @EnvironmentObject private var store: DataStore
    @Environment(\.dismiss) private var dismiss

    let editingEntry: ProgressEntry?

    @State private var date: Date = Date()
    @State private var weightText: String = ""
    @State private var bodyFatText: String = ""
    @State private var notes: String = ""

    /// Stores newly chosen images or loaded existing images
    @State private var images: [PhotoAngle: UIImage] = [:]
    /// Tracks which angles were modified when editing
    @State private var modifiedAngles: Set<PhotoAngle> = []

    @State private var activeCameraAngle: PhotoAngle?
    @State private var pickerItems: [PhotoAngle: PhotosPickerItem?] = [:]
    @State private var errorMessage: String?

    init(editingEntry: ProgressEntry? = nil) {
        self.editingEntry = editingEntry
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("القياسات") {
                    DatePicker("التاريخ", selection: $date, displayedComponents: .date)

                    HStack {
                        Text("الوزن (كغم)")
                        Spacer()
                        TextField("مثال: 80.5", text: $weightText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.leading)
                            .frame(width: 110)
                    }

                    HStack {
                        Text("نسبة الدهون % (اختياري)")
                        Spacer()
                        TextField("مثال: 15.0", text: $bodyFatText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.leading)
                            .frame(width: 110)
                    }
                }

                Section {
                    ForEach(PhotoAngle.allCases) { angle in
                        photoSlotRow(for: angle)
                    }
                } header: {
                    Text("صور التطور (تُحفظ داخل التطبيق فقط)")
                } footer: {
                    Text("كاميرا التطابق تعرض آخر صورة التقطتها بنفس الزاوية بشفافية لمساعدتك على الوقوف بنفس المسافة.")
                }

                Section("ملاحظات") {
                    TextField("مثال: صباحاً قبل الإفطار، إضاءة طبيعية...", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle(editingEntry == nil ? "تسجيل جديد" : "تعديل التسجيل")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إلغاء") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("حفظ") { save() }
                        .bold()
                }
            }
            .onAppear(perform: loadInitialData)
            .fullScreenCover(item: $activeCameraAngle) { angle in
                GhostCameraView(
                    angle: angle,
                    ghostImage: store.latestPhoto(for: angle, excluding: editingEntry?.id)
                ) { captured in
                    images[angle] = captured
                    modifiedAngles.insert(angle)
                }
            }
        }
    }

    @ViewBuilder
    private func photoSlotRow(for angle: PhotoAngle) -> some View {
        let currentImg = images[angle]
        let pickerBinding = Binding<PhotosPickerItem?>(
            get: { pickerItems[angle] ?? nil },
            set: { newItem in
                pickerItems[angle] = newItem
                if let item = newItem {
                    Task {
                        if let data = try? await item.loadTransferable(type: Data.self),
                           let uiImg = UIImage(data: data) {
                            await MainActor.run {
                                images[angle] = uiImg.normalizedUp(maxDimension: 1600)
                                modifiedAngles.insert(angle)
                            }
                        }
                    }
                }
            }
        )

        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 64, height: 84)

                if let img = currentImg {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 64, height: 84)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    Image(systemName: angle.systemImage)
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(angle.arabicTitle)
                    .font(.headline)

                HStack(spacing: 10) {
                    Button {
                        activeCameraAngle = angle
                    } label: {
                        Label("كاميرا", systemImage: "camera.fill")
                            .font(.caption.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.accentColor.opacity(0.18), in: Capsule())
                    }
                    .buttonStyle(.plain)

                    PhotosPicker(selection: pickerBinding, matching: .images) {
                        Label("استيراد", systemImage: "photo")
                            .font(.caption.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.secondary.opacity(0.18), in: Capsule())
                    }
                    .buttonStyle(.plain)

                    if currentImg != nil {
                        Button(role: .destructive) {
                            images.removeValue(forKey: angle)
                            modifiedAngles.insert(angle)
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption)
                                .foregroundColor(.red)
                                .padding(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func loadInitialData() {
        guard let entry = editingEntry else {
            if let lastWeight = store.latestEntry?.weightKg {
                weightText = NumberParser.formatWeight(lastWeight)
            }
            return
        }
        date = entry.date
        weightText = NumberParser.formatWeight(entry.weightKg)
        if let bf = entry.bodyFatPercent {
            bodyFatText = String(format: "%.1f", bf)
        }
        notes = entry.notes
        for angle in PhotoAngle.allCases {
            if let img = store.loadImage(filename: entry.filename(for: angle)) {
                images[angle] = img
            }
        }
    }

    private func save() {
        guard let weight = NumberParser.parseDouble(weightText), weight > 20, weight < 350 else {
            errorMessage = "يرجى إدخال وزن صحيح (بين 20 و 350 كغم)."
            return
        }

        var bodyFat: Double? = nil
        let trimmedBF = bodyFatText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedBF.isEmpty {
            guard let parsedBF = NumberParser.parseDouble(trimmedBF), parsedBF > 2, parsedBF < 70 else {
                errorMessage = "يرجى إدخال نسبة دهون صحيحة (بين 2% و 70%) أو ترك الحقل فارغاً."
                return
            }
            bodyFat = parsedBF
        }

        if let existing = editingEntry {
            var updates: [PhotoAngle: UIImage?] = [:]
            for angle in modifiedAngles {
                updates[angle] = images[angle]
            }
            store.updateEntry(
                existing,
                date: date,
                weightKg: weight,
                bodyFatPercent: bodyFat,
                notes: notes,
                updatedImages: updates
            )
        } else {
            store.addEntry(
                date: date,
                weightKg: weight,
                bodyFatPercent: bodyFat,
                notes: notes,
                images: images
            )
        }
        dismiss()
    }
}
