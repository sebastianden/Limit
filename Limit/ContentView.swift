//
//  ContentView.swift
//  Limit
//
//  Created by STDG (Sebastian Dengler) on 22.02.26.
//

import SwiftUI
import Charts

struct ContentView: View {
    @StateObject private var bluetoothManager = BluetoothManager()
    @StateObject private var persistenceManager = PersistenceManager.shared

    var body: some View {
        TabView {
            // Max Force Test Tab
            maxForceTestTab
                .tabItem {
                    Label("Max Force", systemImage: "bolt.fill")
                }

            // Critical Force Test Tab
            criticalForceTestTab
                .tabItem {
                    Label("Critical Force", systemImage: "timer")
                }

            // History Tab
            HistoryView(persistenceManager: persistenceManager)
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
        }
    }

    private var maxForceTestTab: some View {
        NavigationStack {
            if bluetoothManager.isConnected {
                MaxForceTestView(bluetoothManager: bluetoothManager)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 8, height: 8)
                                Text("Connected")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize()
                            }
                        }

                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Disconnect") {
                                bluetoothManager.disconnect()
                            }
                            .font(.caption)
                            .fixedSize()
                        }
                    }
            } else {
                connectionView
            }
        }
    }

    private var criticalForceTestTab: some View {
        NavigationStack {
            if bluetoothManager.isConnected {
                CriticalForceTestView(bluetoothManager: bluetoothManager)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 8, height: 8)
                                Text("Connected")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize()
                            }
                        }

                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Disconnect") {
                                bluetoothManager.disconnect()
                            }
                            .font(.caption)
                            .fixedSize()
                        }
                    }
            } else {
                connectionView
            }
        }
    }

    private var connectionView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "scale.3d")
                .font(.system(size: 80))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 10, height: 10)

                    Text(bluetoothManager.connectionStatus)
                        .font(.headline)
                }

                Text("Connect to IF_B7 scale to begin")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button(action: {
                if bluetoothManager.isScanning {
                    bluetoothManager.stopScanning()
                } else {
                    bluetoothManager.startScanning()
                }
            }) {
                Label(
                    bluetoothManager.isScanning ? "Stop Scanning" : "Start Scanning",
                    systemImage: bluetoothManager.isScanning ? "stop.circle" : "antenna.radiowaves.left.and.right"
                )
                .frame(maxWidth: 280)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Spacer()
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
