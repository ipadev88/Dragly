//
//  SettingsView.swift
//  Dragly
//
//  Units, rollout, custom intervals.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage(AppSettings.unitKey) private var unitRaw = SpeedUnit.kmh.rawValue
    @AppStorage(AppSettings.rolloutKey) private var rollout = true
    @State private var customs: [CustomInterval] = AppSettings.customIntervals
    @State private var showAdd = false

    private var unit: SpeedUnit { SpeedUnit(rawValue: unitRaw) ?? .kmh }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Units")) {
                    Picker(selection: $unitRaw) {
                        Text(verbatim: "km/h").tag(SpeedUnit.kmh.rawValue)
                        Text(verbatim: "mph").tag(SpeedUnit.mph.rawValue)
                    } label: {
                        Text("Speed")
                    }
                    .pickerStyle(.segmented)
                }
                .listRowBackground(Theme.panel)

                Section {
                    Toggle(isOn: $rollout) {
                        Text("1-foot rollout")
                    }
                    .tint(Theme.accent)
                } header: {
                    Text("Measurement")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Drag-strip style: the clock starts after the first foot of movement.")
                        Text("Measuring continues with the screen off or in another app — a blue indicator shows while it runs.")
                    }
                }
                .listRowBackground(Theme.panel)

                Section {
                    ForEach(customs) { c in
                        Text(verbatim: c.title)
                            .font(.system(.body, design: .rounded).weight(.semibold))
                    }
                    .onDelete { offsets in
                        customs.remove(atOffsets: offsets)
                        AppSettings.saveCustomIntervals(customs)
                    }
                    Button {
                        showAdd = true
                    } label: {
                        Label("Add interval", systemImage: "plus")
                            .foregroundStyle(Theme.accent)
                    }
                } header: {
                    Text("Custom intervals")
                } footer: {
                    Text("Measured automatically in every run, e.g. 130–170.")
                }
                .listRowBackground(Theme.panel)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(Text("Settings"))
            .sheet(isPresented: $showAdd) {
                AddIntervalSheet(unit: unit) { interval in
                    customs.append(interval)
                    AppSettings.saveCustomIntervals(customs)
                }
                .presentationDetents([.height(280)])
                .preferredColorScheme(.dark)
            }
        }
    }
}

private struct AddIntervalSheet: View {
    @Environment(\.dismiss) private var dismiss
    let unit: SpeedUnit
    let onAdd: (CustomInterval) -> Void

    @State private var fromText = ""
    @State private var toText = ""

    private var parsed: (Double, Double)? {
        guard let f = Double(fromText.replacingOccurrences(of: ",", with: ".")),
              let t = Double(toText.replacingOccurrences(of: ",", with: ".")),
              f >= 0, t > f, t <= 600 else { return nil }
        return (f, t)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("From")
                        Spacer()
                        TextField("100", text: $fromText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                        Text(unit.symbol).foregroundStyle(Theme.textSecondary)
                    }
                    HStack {
                        Text("To")
                        Spacer()
                        TextField("200", text: $toText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                        Text(unit.symbol).foregroundStyle(Theme.textSecondary)
                    }
                }
                .listRowBackground(Theme.panel)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(Text("Add interval"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let (f, t) = parsed {
                            onAdd(CustomInterval(from: f, to: t, unit: unit))
                            dismiss()
                        }
                    }
                    .disabled(parsed == nil)
                }
            }
        }
    }
}
