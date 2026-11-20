import SwiftUI
import LocalAuthentication

@main
struct PhysiqueTrackApp: App {
    @StateObject private var store = DataStore()
    @AppStorage("appLockEnabled") private var appLockEnabled: Bool = false
    @AppStorage("appTheme") private var appThemeRaw: String = AppThemeOption.dark.rawValue
    @Environment(\.scenePhase) private var scenePhase

    @State private var isUnlocked: Bool = false
    @State private var authError: String?

    private var preferredScheme: ColorScheme? {
        switch AppThemeOption(rawValue: appThemeRaw) ?? .dark {
        case .dark: return .dark
        case .light: return .light
        case .system: return nil
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if !appLockEnabled || isUnlocked {
                    MainTabView()
                        .environmentObject(store)
                } else {
                    lockScreenView
                }
            }
            .environment(\.layoutDirection, .rightToLeft)
            .preferredColorScheme(preferredScheme)
            .onAppear {
                if appLockEnabled && !isUnlocked {
                    authenticate()
                }
            }
            .onChange(of: scenePhase) { phase in
                if phase == .background && appLockEnabled {
                    isUnlocked = false
                } else if phase == .active && appLockEnabled && !isUnlocked {
                    authenticate()
                }
            }
        }
    }

    private var lockScreenView: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)
            Text("التطبيق مقفل")
                .font(.title2.bold())
            Text("استخدم Face ID أو رمز الجهاز لفتح صورك الخاصة")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if let err = authError {
                Text(err)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            Button {
                authenticate()
            } label: {
                Label("فتح القفل", systemImage: "faceid")
                    .font(.headline)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private func authenticate() {
        let context = LAContext()
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "افتح التطبيق لعرض صور وتطور الوزن"
            ) { success, evalError in
                DispatchQueue.main.async {
                    if success {
                        self.isUnlocked = true
                        self.authError = nil
                    } else {
                        self.authError = evalError?.localizedDescription
                    }
                }
            }
        } else {
            isUnlocked = true
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            TimelineView()
                .tabItem {
                    Label("السجل", systemImage: "list.bullet.rectangle.portrait")
                }

            CompareView()
                .tabItem {
                    Label("المقارنة", systemImage: "rectangle.split.2x1")
                }

            ChartsView()
                .tabItem {
                    Label("التطور", systemImage: "chart.xyaxis.line")
                }

            SettingsView()
                .tabItem {
                    Label("الإعدادات", systemImage: "gearshape")
                }
        }
    }
}
