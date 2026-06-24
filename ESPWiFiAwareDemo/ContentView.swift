//
//  ContentView.swift
//  ESP Wi-Fi Aware Demo
//

import AccessorySetupKit
import SwiftUI

struct ContentView: View {

    @State private var log: MessageLog
    @State private var accessoryManager: AccessoryManager
    @State private var showingPairedDevices = false
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let log = MessageLog()
        _log = State(wrappedValue: log)
        _accessoryManager = State(wrappedValue: AccessoryManager(log: log))
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Wi-Fi Aware UDP Demo")
                .font(.headline)

            VStack(spacing: 12) {
                Button {
                    accessoryManager.showPicker()
                } label: {
                    Label("Pair New Device", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    accessoryManager.refreshPairedAccessories()
                    showingPairedDevices = true
                } label: {
                    Label("Paired Devices", systemImage: "cpu")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(role: .destructive) {
                    accessoryManager.disconnect()
                } label: {
                    Label("Disconnect", systemImage: "xmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
            .padding(.horizontal)

            ConsoleView(log: log)
        }
        .padding()
        .onAppear {
            accessoryManager.activate()
        }
        // Tear the data path down whenever the app leaves the foreground
        // (backgrounded, or on its way to being terminated). Wi-Fi Aware can't
        // run in the background, so holding the connection there is pointless.
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active {
                accessoryManager.disconnect()
            }
        }
        .sheet(isPresented: $showingPairedDevices) {
            PairedDevicesView(manager: accessoryManager)
        }
    }
}

/// Lists accessories already paired through AccessorySetupKit and lets the user
/// trigger a Wi-Fi Aware connection to one of them without a fresh pairing flow.
private struct PairedDevicesView: View {
    let manager: AccessoryManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if manager.pairedAccessories.isEmpty {
                    ContentUnavailableView(
                        "No Paired Devices",
                        systemImage: "cpu",
                        description: Text("Use “Show picker” to pair an ESP32 first.")
                    )
                } else {
                    ForEach(Array(manager.pairedAccessories.enumerated()), id: \.offset) { _, accessory in
                        Button {
                            manager.connect(to: accessory)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "cpu")
                                    .foregroundStyle(.tint)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(accessory.displayName)
                                    Text("Connect without pairing")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "wifi")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Paired Devices")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

private struct ConsoleView: View {
    let log: MessageLog

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Console")
                    .font(.caption.weight(.semibold))
                Spacer()
                Button("Clear") { log.clear() }
                    .font(.caption)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        if log.lines.isEmpty {
                            Text("waiting…")
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(.green.opacity(0.6))
                        } else {
                            ForEach(Array(log.lines.enumerated()), id: \.offset) { idx, line in
                                Text(line)
                                    .font(.system(.footnote, design: .monospaced))
                                    .foregroundStyle(.green)
                                    .textSelection(.enabled)
                                    .id(idx)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                }
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .frame(height: 320)
                .onChange(of: log.lines.count) {
                    if let last = log.lines.indices.last {
                        withAnimation(.linear(duration: 0.1)) {
                            proxy.scrollTo(last, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
