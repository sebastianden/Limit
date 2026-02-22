//
//  MaxForceTestView.swift
//  Limit
//
//  Max Force Test UI
//

import SwiftUI
import Charts

struct MaxForceTestView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    @StateObject private var testViewModel = ForceTestViewModel()

    var body: some View {
        VStack(spacing: 16) {
            // Max Force Display
            forceDisplay

            // Real-time Graph
            forceChart

            // Test Controls
            testControls

            Spacer()
        }
        .padding()
    }

    // MARK: - Force Display
    private var forceDisplay: some View {
        HStack(spacing: 16) {
            // Current Force
            VStack(spacing: 8) {
                Text("Current")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%.1f", bluetoothManager.currentForce))
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text("kg")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Max Force
            VStack(spacing: 8) {
                Text("Max")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%.1f", testViewModel.maxForce))
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text("kg")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.green.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Force Chart
    private var forceChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Force Over Time")
                .font(.headline)

            let displayData = testViewModel.last10SecondsData

            Chart(displayData) { dataPoint in
                LineMark(
                    x: .value("Time", dataPoint.timestamp),
                    y: .value("Force", dataPoint.force)
                )
                .foregroundStyle(.blue)
                .interpolationMethod(.stepEnd)

                AreaMark(
                    x: .value("Time", dataPoint.timestamp),
                    y: .value("Force", dataPoint.force)
                )
                .foregroundStyle(.blue.opacity(0.2))
                .interpolationMethod(.stepEnd)
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let force = value.as(Double.self) {
                            Text("\(Int(force)) kg")
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let time = value.as(Double.self) {
                            Text("\(String(format: "%.0f", time))s")
                        }
                    }
                }
            }
            .chartXScale(domain: testViewModel.xAxisRange)
            .frame(height: 200)
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 2)
    }

    // MARK: - Test Controls
    private var testControls: some View {
        HStack(spacing: 16) {
            if !testViewModel.isTestActive {
                Button(action: {
                    testViewModel.startTest(forcePublisher: bluetoothManager.$currentForce)
                }) {
                    Label("Start Test", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                Button(action: {
                    testViewModel.stopTest()
                }) {
                    Label("Stop Test", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .controlSize(.large)
            }

            Button(action: {
                testViewModel.resetTest()
            }) {
                Label("Reset", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(testViewModel.isTestActive)
        }
    }
}
