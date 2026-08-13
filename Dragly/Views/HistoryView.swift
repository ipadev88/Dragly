//
//  HistoryView.swift
//  Dragly
//
//  Saved runs list + detail.
//

import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppearanceModel.self) private var appearance
    @Query(sort: \RunRecord.date, order: .reverse) private var records: [RunRecord]
    @AppStorage(AppSettings.unitKey) private var unitRaw = SpeedUnit.kmh.rawValue

    @State private var pendingDelete: RunRecord?
    @State private var confirmDeleteAll = false

    private var unit: SpeedUnit { SpeedUnit(rawValue: unitRaw) ?? .kmh }
    private var accent: Color { appearance.accent.color }

    var body: some View {
        NavigationStack {
            Group {
                if records.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(Text("History"))
            .toolbar {
                if !records.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button(role: .destructive) {
                            confirmDeleteAll = true
                        } label: {
                            Label("Delete all", systemImage: "trash")
                        }
                        .tint(Theme.danger)
                    }
                }
            }
            .alert(Text("Delete this run?"), isPresented: deleteOneBinding, presenting: pendingDelete) { record in
                Button("Delete", role: .destructive) { delete(record) }
                Button("Cancel", role: .cancel) { pendingDelete = nil }
            } message: { record in
                Text("\(record.headline(unit: unit) ?? "—") · \(record.date.formatted(date: .abbreviated, time: .shortened)). This can't be undone.")
            }
            .task {
                #if DEBUG
                // Screenshot hook: the simulator can't be touch-driven here.
                if ProcessInfo.processInfo.arguments.contains("--alert-demo") {
                    pendingDelete = records.first
                }
                #endif
            }
            .alert(Text("Delete all runs?"), isPresented: $confirmDeleteAll) {
                Button("Delete all", role: .destructive) { deleteAll() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("All \(records.count) saved runs will be removed. This can't be undone.")
            }
        }
    }

    private var deleteOneBinding: Binding<Bool> {
        Binding(get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } })
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "flag.checkered")
                .font(.system(size: 44))
                .foregroundStyle(Theme.textTertiary)
            Text("No runs yet")
                .font(.label(18, weight: .bold))
                .foregroundStyle(Theme.textSecondary)
            Text("Your measured runs will appear here")
                .font(.label(14, weight: .regular))
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        List {
            ForEach(records) { record in
                NavigationLink {
                    RunDetailView(record: record, unit: unit)
                } label: {
                    row(record)
                }
                .listRowBackground(Theme.panel)
                .listRowSeparatorTint(Theme.panelStroke)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        pendingDelete = record
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func row(_ record: RunRecord) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: record.standingStart ? "flag.checkered" : "gauge.open.with.lines.needle.33percent")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(accent)
                Text(record.date, format: .dateTime.day().month().year().hour().minute())
                    .font(.label(13, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                if !record.usedMotion {
                    Text("GPS-only")
                        .font(.caption(10))
                        .foregroundStyle(Theme.warning)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Theme.warning.opacity(0.13), in: Capsule())
                }
            }
            HStack {
                Text(verbatim: record.headline(unit: unit) ?? "—")
                    .font(.figureAccent(16))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(verbatim: "↑ \(Int(unit.convert(record.peakSpeedMS).rounded())) \(unit.symbolText)")
                    .font(.figure(13, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.vertical, 3)
    }

    private func delete(_ record: RunRecord) {
        context.delete(record)
        try? context.save()
        pendingDelete = nil
    }

    private func deleteAll() {
        for record in records { context.delete(record) }
        try? context.save()
    }
}

struct RunDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let record: RunRecord
    let unit: SpeedUnit

    @State private var confirmDelete = false

    var body: some View {
        Group {
            if let result = record.result {
                RunResultView(result: result, unit: unit)
            } else {
                Text(verbatim: "—")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.background.ignoresSafeArea())
            }
        }
        .navigationTitle(Text("Run"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .destructiveAction) {
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Image(systemName: "trash")
                }
                .tint(Theme.danger)
            }
        }
        .alert(Text("Delete this run?"), isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                context.delete(record)
                try? context.save()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
    }
}
