import SwiftUI

struct TimelineView: View {
    @EnvironmentObject private var store: DataStore
    @State private var showingAddSheet = false
    @State private var selectedEntry: ProgressEntry?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    summaryCards

                    if store.entries.isEmpty {
                        emptyStateView
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(store.entries) { entry in
                                EntryRowCard(entry: entry)
                                    .onTapGesture {
                                        selectedEntry = entry
                                    }
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("تطور الوزن")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Label("إضافة", systemImage: "plus.circle.fill")
                            .font(.title3)
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                AddEditEntryView()
            }
            .sheet(item: $selectedEntry) { entry in
                EntryDetailView(entryId: entry.id)
            }
        }
    }

    private var summaryCards: some View {
        HStack(spacing: 10) {
            statCard(
                title: "الوزن الحالي",
                value: store.latestEntry.map { "\(NumberParser.formatWeight($0.weightKg)) كغم" } ?? "—",
                icon: "scalemass.fill",
                tint: .accentColor
            )

            statCard(
                title: "إجمالي التغيّر",
                value: {
                    guard let delta = store.totalWeightChange else { return "—" }
                    let sign = delta > 0 ? "+" : ""
                    return "\(sign)\(NumberParser.formatWeight(delta)) كغم"
                }(),
                icon: "arrow.up.arrow.down",
                tint: (store.totalWeightChange ?? 0) <= 0 ? .green : .orange
            )

            statCard(
                title: "نسبة الدهون",
                value: store.latestEntry?.bodyFatPercent.map { NumberParser.formatPercent($0) } ?? "—",
                icon: "percent",
                tint: .cyan
            )
        }
    }

    private func statCard(title: String, value: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(tint)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Text(value)
                .font(.headline.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private var emptyStateView: some View {
        VStack(spacing: 14) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 52))
                .foregroundColor(.accentColor)
            Text("ابدأ بتوثيق رحلتك")
                .font(.title3.bold())
            Text("أضف أول تسجيل للوزن وصور التطور، وسيقوم التطبيق بحفظها محلياً بخصوصية تامة.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button {
                showingAddSheet = true
            } label: {
                Label("إضافة أول تسجيل", systemImage: "plus")
                    .font(.headline)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
        }
        .padding(.vertical, 48)
        .padding(.horizontal)
    }
}

struct EntryRowCard: View {
    @EnvironmentObject private var store: DataStore
    let entry: ProgressEntry

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "ar")
        df.dateStyle = .medium
        return df
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(NumberParser.formatWeight(entry.weightKg)) كغم")
                    .font(.title3.bold().monospacedDigit())

                if let bf = entry.bodyFatPercent {
                    Text("• دهون \(NumberParser.formatPercent(bf))")
                        .font(.subheadline)
                        .foregroundColor(.cyan)
                }

                Spacer()

                Text(Self.dateFormatter.string(from: entry.date))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if !entry.notes.isEmpty {
                Text(entry.notes)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                ForEach(PhotoAngle.allCases) { angle in
                    if let img = store.loadImage(filename: entry.filename(for: angle)) {
                        ZStack(alignment: .bottomLeading) {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity)
                                .frame(height: 115)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            Text(angle.arabicTitle)
                                .font(.caption2.bold())
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.black.opacity(0.6), in: Capsule())
                                .padding(5)
                        }
                    } else {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.secondary.opacity(0.1))
                            .frame(maxWidth: .infinity)
                            .frame(height: 115)
                            .overlay {
                                VStack(spacing: 4) {
                                    Image(systemName: angle.systemImage)
                                        .foregroundColor(.secondary.opacity(0.6))
                                    Text(angle.arabicTitle)
                                        .font(.caption2)
                                        .foregroundColor(.secondary.opacity(0.7))
                                }
                            }
                    }
                }
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

struct EntryDetailView: View {
    @EnvironmentObject private var store: DataStore
    @Environment(\.dismiss) private var dismiss

    let entryId: UUID
    @State private var showingEdit = false
    @State private var showingDeleteConfirm = false
    @State private var zoomedImage: UIImage?

    private var entry: ProgressEntry? {
        store.entries.first { $0.id == entryId }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let entry = entry {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(NumberParser.formatWeight(entry.weightKg)) كغم")
                                        .font(.largeTitle.bold().monospacedDigit())
                                    if let bf = entry.bodyFatPercent {
                                        Text("نسبة الدهون: \(NumberParser.formatPercent(bf))")
                                            .font(.subheadline)
                                            .foregroundColor(.cyan)
                                    }
                                }
                                Spacer()
                                Text(entry.date, style: .date)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }

                            if !entry.notes.isEmpty {
                                Text(entry.notes)
                                    .font(.body)
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                            }

                            ForEach(PhotoAngle.allCases) { angle in
                                if let img = store.loadImage(filename: entry.filename(for: angle)) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("الزاوية: \(angle.arabicTitle)")
                                            .font(.headline)
                                        Image(uiImage: img)
                                            .resizable()
                                            .scaledToFit()
                                            .clipShape(RoundedRectangle(cornerRadius: 14))
                                            .onTapGesture {
                                                zoomedImage = img
                                            }
                                    }
                                }
                            }

                            Button(role: .destructive) {
                                showingDeleteConfirm = true
                            } label: {
                                Label("حذف هذا التسجيل", systemImage: "trash")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                            }
                            .buttonStyle(.bordered)
                            .padding(.top, 8)
                        }
                        .padding()
                    }
                    .sheet(isPresented: $showingEdit) {
                        AddEditEntryView(editingEntry: entry)
                    }
                    .confirmationDialog("هل أنت متأكد من حذف هذا التسجيل وصوره؟", isPresented: $showingDeleteConfirm, titleVisibility: .visible) {
                        Button("حذف نهائياً", role: .destructive) {
                            store.deleteEntry(entry)
                            dismiss()
                        }
                        Button("إلغاء", role: .cancel) {}
                    }
                } else {
                    Text("التسجيل غير موجود")
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("تفاصيل التسجيل")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إغلاق") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("تعديل") { showingEdit = true }
                }
            }
            .fullScreenCover(isPresented: Binding(
                get: { zoomedImage != nil },
                set: { if !$0 { zoomedImage = nil } }
            )) {
                if let img = zoomedImage {
                    ZoomableImageView(image: img) { zoomedImage = nil }
                }
            }
        }
    }
}

struct ZoomableImageView: View {
    let image: UIImage
    let onClose: () -> Void
    @State private var scale: CGFloat = 1.0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            scale = max(1.0, min(value, 4.0))
                        }
                        .onEnded { _ in
                            if scale < 1.1 { withAnimation { scale = 1.0 } }
                        }
                )
                .onTapGesture(count: 2) {
                    withAnimation { scale = (scale > 1.0) ? 1.0 : 2.2 }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
                    .padding()
            }
        }
    }
}
