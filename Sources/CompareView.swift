import SwiftUI

enum CompareMode: String, CaseIterable, Identifiable {
    case sideBySide
    case slider

    var id: String { rawValue }
    var title: String {
        switch self {
        case .sideBySide: return "جنباً إلى جنب"
        case .slider: return "شريط السحب"
        }
    }
}

struct CompareView: View {
    @EnvironmentObject private var store: DataStore

    @State private var selectedAngle: PhotoAngle = .front
    @State private var compareMode: CompareMode = .sideBySide
    @State private var beforeEntryId: UUID?
    @State private var afterEntryId: UUID?
    @State private var sliderPosition: CGFloat = 0.5

    private var entriesWithAngle: [ProgressEntry] {
        store.sortedChronological.filter { $0.filename(for: selectedAngle) != nil }
    }

    private var beforeEntry: ProgressEntry? {
        entriesWithAngle.first { $0.id == beforeEntryId } ?? entriesWithAngle.first
    }

    private var afterEntry: ProgressEntry? {
        entriesWithAngle.first { $0.id == afterEntryId } ?? entriesWithAngle.last
    }

    private static let shortDate: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "ar")
        df.dateStyle = .short
        return df
    }()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("الزاوية", selection: $selectedAngle) {
                        ForEach(PhotoAngle.allCases) { angle in
                            Text(angle.arabicTitle).tag(angle)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedAngle) { _ in
                        syncDefaultSelection()
                    }

                    if entriesWithAngle.count < 2 {
                        VStack(spacing: 12) {
                            Image(systemName: "rectangle.split.2x1")
                                .font(.system(size: 46))
                                .foregroundColor(.secondary)
                            Text("أضف صورتين على الأقل لزاوية (\(selectedAngle.arabicTitle)) للمقارنة")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.vertical, 60)
                    } else {
                        Picker("طريقة العرض", selection: $compareMode) {
                            ForEach(CompareMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        selectionPickers

                        if let before = beforeEntry, let after = afterEntry {
                            deltaSummaryBar(before: before, after: after)

                            if let beforeImg = store.loadImage(filename: before.filename(for: selectedAngle)),
                               let afterImg = store.loadImage(filename: after.filename(for: selectedAngle)) {
                                if compareMode == .sideBySide {
                                    sideBySideView(before: before, beforeImg: beforeImg, after: after, afterImg: afterImg)
                                } else {
                                    sliderCompareView(beforeImg: beforeImg, afterImg: afterImg)
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("المقارنة")
            .onAppear(perform: syncDefaultSelection)
        }
    }

    private func syncDefaultSelection() {
        let list = entriesWithAngle
        guard list.count >= 2 else {
            beforeEntryId = nil
            afterEntryId = nil
            return
        }
        if beforeEntryId == nil || !list.contains(where: { $0.id == beforeEntryId }) {
            beforeEntryId = list.first?.id
        }
        if afterEntryId == nil || !list.contains(where: { $0.id == afterEntryId }) {
            afterEntryId = list.last?.id
        }
    }

    private var selectionPickers: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("قبل")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                Picker("قبل", selection: Binding(
                    get: { beforeEntry?.id ?? UUID() },
                    set: { beforeEntryId = $0 }
                )) {
                    ForEach(entriesWithAngle) { entry in
                        Text("\(Self.shortDate.string(from: entry.date)) (\(NumberParser.formatWeight(entry.weightKg)))")
                            .tag(entry.id)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity)
                .padding(8)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("بعد")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                Picker("بعد", selection: Binding(
                    get: { afterEntry?.id ?? UUID() },
                    set: { afterEntryId = $0 }
                )) {
                    ForEach(entriesWithAngle) { entry in
                        Text("\(Self.shortDate.string(from: entry.date)) (\(NumberParser.formatWeight(entry.weightKg)))")
                            .tag(entry.id)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity)
                .padding(8)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func deltaSummaryBar(before: ProgressEntry, after: ProgressEntry) -> some View {
        let weightDiff = after.weightKg - before.weightKg
        let days = Calendar.current.dateComponents([.day], from: before.date, to: after.date).day ?? 0
        let sign = weightDiff > 0 ? "+" : ""

        return HStack {
            VStack(spacing: 2) {
                Text("فارق الوزن")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("\(sign)\(NumberParser.formatWeight(weightDiff)) كغم")
                    .font(.headline.monospacedDigit())
                    .foregroundColor(weightDiff <= 0 ? .green : .orange)
            }
            .frame(maxWidth: .infinity)

            Divider().frame(height: 28)

            VStack(spacing: 2) {
                Text("المدة الزمنية")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("\(abs(days)) يوم")
                    .font(.headline.monospacedDigit())
            }
            .frame(maxWidth: .infinity)

            if let bf1 = before.bodyFatPercent, let bf2 = after.bodyFatPercent {
                let bfDiff = bf2 - bf1
                let bfSign = bfDiff > 0 ? "+" : ""
                Divider().frame(height: 28)
                VStack(spacing: 2) {
                    Text("فارق الدهون")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("\(bfSign)\(String(format: "%.1f%%", bfDiff))")
                        .font(.headline.monospacedDigit())
                        .foregroundColor(.cyan)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func sideBySideView(
        before: ProgressEntry,
        beforeImg: UIImage,
        after: ProgressEntry,
        afterImg: UIImage
    ) -> some View {
        HStack(spacing: 8) {
            VStack(spacing: 6) {
                Image(uiImage: beforeImg)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                Text("قبل • \(NumberParser.formatWeight(before.weightKg)) كغم")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 6) {
                Image(uiImage: afterImg)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                Text("بعد • \(NumberParser.formatWeight(after.weightKg)) كغم")
                    .font(.caption.bold())
                    .foregroundColor(.accentColor)
            }
        }
    }

    private func sliderCompareView(beforeImg: UIImage, afterImg: UIImage) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let splitX = max(16, min(w - 16, w * sliderPosition))

            ZStack(alignment: .leading) {
                Image(uiImage: afterImg)
                    .resizable()
                    .scaledToFill()
                    .frame(width: w, height: h)
                    .clipped()

                Image(uiImage: beforeImg)
                    .resizable()
                    .scaledToFill()
                    .frame(width: w, height: h)
                    .clipped()
                    .mask(
                        HStack(spacing: 0) {
                            Rectangle().frame(width: splitX)
                            Spacer(minLength: 0)
                        }
                    )

                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2.5, height: h)
                    .offset(x: splitX - 1.25)

                Circle()
                    .fill(Color.white)
                    .frame(width: 36, height: 36)
                    .shadow(radius: 4)
                    .overlay {
                        Image(systemName: "arrow.left.and.right")
                            .font(.caption.bold())
                            .foregroundColor(.black)
                    }
                    .offset(x: splitX - 18)

                VStack {
                    HStack {
                        Text("قبل")
                            .font(.caption.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.6), in: Capsule())
                        Spacer()
                        Text("بعد")
                            .font(.caption.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.85), in: Capsule())
                    }
                    .padding(12)
                    Spacer()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        sliderPosition = max(0.05, min(0.95, value.location.x / w))
                    }
            )
        }
        .environment(\.layoutDirection, .leftToRight)
        .frame(height: 440)
    }
}
