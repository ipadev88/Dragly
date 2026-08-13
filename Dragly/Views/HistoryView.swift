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
    @Query(sort: \RunRecord.date, order: .reverse) private var records: [RunRecord]
    @AppStorage(AppSettings.unitKey) private var unitRaw = SpeedUnit.kmh.rawValue

    private var unit: SpeedUnit { SpeedUnit(rawValue: unitRaw) ?? .kmh }

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
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "flag.checkered")
                .font(.system(size: 44))
                .foregroundStyle(Theme.textTertiary)
            Text("No runs yet")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
            Text("Your measured runs will appear here")
                .font(.system(size: 14, design: .rounded))
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
            }
            .onDelete { offsets in
                for i in offsets { context.delete(records[i]) }
                try? context.save()
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func row(_ record: RunRecord) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: record.standingStart ? "flag.checkered" : "gauge.open.with.lines.needle.33percent")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.accent)
                Text(record.date, format: .dateTime.day().month().year().hour().minute())
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                if !record.usedMotion {
                    Text("GPS-only")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.warning)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Theme.warning.opacity(0.13), in: Capsule())
                }
            }
            HStack {
                Text(verbatim: record.headline(unit: unit) ?? "—")
                    .font(.system(size: 17, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(verbatim: "↑ \(Int(unit.convert(record.peakSpeedMS).rounded())) \(unit.symbolText)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.vertical, 3)
    }
}

struct RunDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let record: RunRecord
    let unit: SpeedUnit

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
                    context.delete(record)
                    try? context.save()
                    dismiss()
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
    }
}
