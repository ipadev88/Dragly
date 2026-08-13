//
//  SettingsView.swift
//  Dragly
//
//  Units, appearance, rollout, custom intervals, reset.
//

import SwiftUI

struct SettingsView: View {
    @Environment(AppearanceModel.self) private var appearance
    @AppStorage(AppSettings.unitKey) private var unitRaw = SpeedUnit.kmh.rawValue
    @AppStorage(AppSettings.rolloutKey) private var rollout = true
    @State private var customs: [CustomInterval] = AppSettings.customIntervals
    @State private var showAdd = false
    @State private var confirmReset = false

    private var unit: SpeedUnit { SpeedUnit(rawValue: unitRaw) ?? .kmh }
    private var accent: Color { appearance.accent.color }

    var body: some View {
        @Bindable var appearance = appearance
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

                Section(header: Text("Appearance")) {
                    Picker(selection: $appearance.scheme) {
                        ForEach(AppearanceChoice.allCases) { choice in
                            Text(choice.title).tag(choice)
                        }
                    } label: {
                        Text("Theme")
                    }
                    .pickerStyle(.segmented)

                    accentPicker
                }
                .listRowBackground(Theme.panel)

                Section {
                    Toggle(isOn: $rollout) {
                        Text("1-foot rollout")
                    }
                    .tint(accent)
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
                            .font(.label(17))
                    }
                    .onDelete { offsets in
                        customs.remove(atOffsets: offsets)
                        AppSettings.saveCustomIntervals(customs)
                    }
                    Button {
                        showAdd = true
                    } label: {
                        Label("Add interval", systemImage: "plus")
                            .foregroundStyle(accent)
                    }
                } header: {
                    Text("Custom intervals")
                } footer: {
                    Text("Measured automatically in every run, e.g. 130–170.")
                }
                .listRowBackground(Theme.panel)

                Section {
                    Button(role: .destructive) {
                        confirmReset = true
                    } label: {
                        Label("Reset settings", systemImage: "arrow.counterclockwise")
                            .foregroundStyle(Theme.danger)
                    }
                } footer: {
                    Text("Restores units, appearance and measurement options. Saved runs are kept.")
                }
                .listRowBackground(Theme.panel)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(Text("Settings"))
            .tint(accent)
            .sheet(isPresented: $showAdd) {
                AddIntervalSheet(unit: unit, accent: accent) { interval in
                    customs.append(interval)
                    AppSettings.saveCustomIntervals(customs)
                }
                .presentationDetents([.height(280)])
                .preferredColorScheme(appearance.scheme.colorScheme)
            }
            .alert(Text("Reset settings?"), isPresented: $confirmReset) {
                Button("Reset", role: .destructive) { resetSettings() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Units, appearance, rollout and custom intervals go back to their defaults. Saved runs are kept.")
            }
        }
    }

    // MARK: Accent swatches

    private var accentPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Accent")
                Spacer()
                Text(appearance.accent.title)
                    .font(.label(15, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            HStack(spacing: 12) {
                ForEach(AccentChoice.allCases) { choice in
                    Button {
                        appearance.accent = choice
                    } label: {
                        Circle()
                            .fill(choice.color)
                            .frame(width: 28, height: 28)
                            .overlay {
                                if choice == appearance.accent {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 13, weight: .black))
                                        .foregroundStyle(choice.onAccent)
                                }
                            }
                            .overlay {
                                Circle()
                                    .strokeBorder(Theme.textPrimary.opacity(choice == appearance.accent ? 0.9 : 0),
                                                  lineWidth: 2)
                                    .padding(-3)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(choice.title)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 4)
        .animation(.snappy(duration: 0.2), value: appearance.accent)
    }

    private func resetSettings() {
        unitRaw = SpeedUnit.kmh.rawValue
        rollout = true
        customs = []
        AppSettings.saveCustomIntervals([])
        appearance.reset()
    }
}

private struct AddIntervalSheet: View {
    @Environment(\.dismiss) private var dismiss
    let unit: SpeedUnit
    let accent: Color
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
                            .font(.figure(17))
                            .frame(width: 90)
                        Text(unit.symbol).foregroundStyle(Theme.textSecondary)
                    }
                    HStack {
                        Text("To")
                        Spacer()
                        TextField("200", text: $toText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .font(.figure(17))
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
            .tint(accent)
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
