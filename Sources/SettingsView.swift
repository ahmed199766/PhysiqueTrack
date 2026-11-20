import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var store: DataStore
    @AppStorage("appLockEnabled") private var appLockEnabled: Bool = false
    @AppStorage("appTheme") private var appThemeRaw: String = AppThemeOption.dark.rawValue

    @State private var showingExporter = false
    @State private var showingImporter = false
    @State private var backupDocument = BackupDocument()
    @State private var alertMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("الخصوصية والأمان") {
                    Toggle(isOn: $appLockEnabled) {
                        Label("قفل التطبيق بـ Face ID أو الرمز", systemImage: "faceid")
                    }
                }

                Section("المظهر") {
                    Picker("السمة", selection: $appThemeRaw) {
                        ForEach(AppThemeOption.allCases) { option in
                            Text(option.title).tag(option.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Button {
                        exportBackup()
                    } label: {
                        Label("تصدير نسخة احتياطية (مع الصور)", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        showingImporter = true
                    } label: {
                        Label("استيراد نسخة احتياطية", systemImage: "square.and.arrow.down")
                    }
                } header: {
                    Text("النسخ الاحتياطي")
                } footer: {
                    Text("يتم حفظ جميع الصور داخل التطبيق فقط ولا تظهر في استوديو الآيفون. استخدم النسخ الاحتياطي لحفظ نسخة على iCloud Drive أو Google Drive قبل حذف التطبيق أو تحديثه.")
                }

                Section("معلومات التخزين المحلي") {
                    HStack {
                        Text("عدد التسجيلات")
                        Spacer()
                        Text("\(store.entries.count)")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("عدد الصور المحفوظة")
                        Spacer()
                        Text("\(store.totalPhotoCount)")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("الإعدادات")
            .fileExporter(
                isPresented: $showingExporter,
                document: backupDocument,
                contentType: .json,
                defaultFilename: backupFilename()
            ) { result in
                switch result {
                case .success:
                    alertMessage = "تم حفظ النسخة الاحتياطية بنجاح."
                case .failure(let error):
                    alertMessage = "تعذر الحفظ: \(error.localizedDescription)"
                }
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.json]
            ) { result in
                switch result {
                case .success(let url):
                    importBackup(from: url)
                case .failure(let error):
                    alertMessage = "تعذر الاستيراد: \(error.localizedDescription)"
                }
            }
            .alert("النسخ الاحتياطي", isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )) {
                Button("حسناً", role: .cancel) {}
            } message: {
                Text(alertMessage ?? "")
            }
        }
    }

    private func backupFilename() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return "PhysiqueTrack_Backup_\(df.string(from: Date()))"
    }

    private func exportBackup() {
        do {
            let data = try store.createBackupData()
            backupDocument = BackupDocument(data: data)
            showingExporter = true
        } catch {
            alertMessage = "حدث خطأ أثناء تجهيز النسخة: \(error.localizedDescription)"
        }
    }

    private func importBackup(from url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }
        do {
            let data = try Data(contentsOf: url)
            let count = try store.importBackupData(data)
            alertMessage = "تم استيراد \(count) تسجيل بنجاح."
        } catch {
            alertMessage = "الملف غير صالح أو تالف: \(error.localizedDescription)"
        }
    }
}
