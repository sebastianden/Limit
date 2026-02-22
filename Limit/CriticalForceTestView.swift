//
//  CriticalForceTestView.swift
//  Limit
//
//  Critical Force Test UI
//

import SwiftUI
import Charts

struct CriticalForceTestView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    @StateObject private var testViewModel = CriticalForceViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if testViewModel.isTestCompleted {
                    resultsView
                } else {
                    // Test interface
                    if testViewModel.isTestActive {
                        phaseIndicator
                    }

                    currentForceDisplay
                    forceChart

                    if testViewModel.isTestActive {
                        progressInfo
                    }

                    testControls
                }
            }
            .padding()
        }
        .onAppear {
            setupHapticFeedback()
        }
    }

    // MARK: - Phase Indicator
    private var phaseIndicator: some View {
        HStack(spacing: 16) {
            // Phase badge
            Text(phaseLabel)
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .frame(width: 95)
                .padding(.vertical, 10)
                .background(phaseColor)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            // Timer
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(String(format: "%.0f", testViewModel.phaseTimeRemaining))
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundColor(phaseColor)
                    .monospacedDigit()
                    .frame(minWidth: 70, alignment: .trailing)

                Text("s")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Instruction
            VStack(alignment: .trailing, spacing: 4) {
                if testViewModel.currentPhase != .preparation {
                    Text("\(testViewModel.currentContraction)/24")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .monospacedDigit()
                } else {
                    Text("Ready")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                }

                Text(phaseInstruction)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(phaseColor.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(phaseColor, lineWidth: 3)
        )
    }

    private var phaseLabel: String {
        switch testViewModel.currentPhase {
        case .preparation: return "GET READY"
        case .work: return "WORK"
        case .rest: return "REST"
        }
    }

    private var phaseColor: Color {
        switch testViewModel.currentPhase {
        case .preparation: return .blue
        case .work: return .green
        case .rest: return .orange
        }
    }

    private var phaseInstruction: String {
        switch testViewModel.currentPhase {
        case .preparation: return "Get in position"
        case .work: return "Max force"
        case .rest: return "Hands down"
        }
    }

    // MARK: - Progress Info
    private var progressInfo: some View {
        VStack(spacing: 6) {
            if testViewModel.currentPhase != .preparation {
                HStack {
                    Text("Progress")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("\(testViewModel.currentContraction) / 24 phases")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            ProgressView(value: testViewModel.progress)
                .tint(testViewModel.currentPhase == .work ? .green : .orange)
        }
        .padding(12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 2)
    }

    // MARK: - Current Metrics Display
    private var currentForceDisplay: some View {
        HStack(spacing: 16) {
            // Current Force - always visible
            metricCard(
                label: "Current",
                value: bluetoothManager.currentForce,
                color: .blue
            )

            // Critical Force when available (after 6+ phases)
            if let cf = testViewModel.currentCriticalForce {
                metricCard(
                    label: "Crit. Force",
                    value: cf,
                    color: .green
                )
            }
        }
    }

    private func metricCard(label: String, value: Double, color: Color) -> some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.headline)
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(String(format: "%.1f", value))
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text("kg")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
            .frame(height: 170)
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

    // MARK: - Results View
    private var resultsView: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Test Complete Header
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.green)

                    Text("Test Complete")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                }
                .padding(.top)

                // Critical Force Result
                VStack(spacing: 12) {
                    Text("Critical Force (CF)")
                        .font(.title2)
                        .fontWeight(.semibold)

                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(String(format: "%.2f", testViewModel.criticalForce ?? 0))
                            .font(.system(size: 56, weight: .bold, design: .rounded))
                            .foregroundColor(.green)

                        Text("kg")
                            .font(.title)
                            .foregroundStyle(.secondary)
                    }

                    Text("Mean force of last 6 phases")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.green.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 16))

                // W' Result
                VStack(spacing: 12) {
                    Text("W' (W-Prime)")
                        .font(.title2)
                        .fontWeight(.semibold)

                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(String(format: "%.1f", testViewModel.wPrime ?? 0))
                            .font(.system(size: 56, weight: .bold, design: .rounded))
                            .foregroundColor(.blue)

                        Text("kg·s")
                            .font(.title)
                            .foregroundStyle(.secondary)
                    }

                    Text("Total impulse above CF")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 16))

                // Phase Summary
                VStack(alignment: .leading, spacing: 12) {
                    Text("Phase Summary")
                        .font(.headline)

                    ForEach(testViewModel.contractions) { contraction in
                        HStack {
                            Text("#\(contraction.contractionNumber)")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .frame(width: 40, alignment: .leading)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Peak: \(String(format: "%.1f", contraction.peakForce)) kg")
                                    .font(.caption)
                                Text("Mean: \(String(format: "%.1f", contraction.meanForce)) kg")
                                    .font(.caption)
                            }

                            Spacer()

                            Text("\(String(format: "%.1f", contraction.impulse)) kg·s")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)

                        if contraction.contractionNumber < testViewModel.contractions.count {
                            Divider()
                        }
                    }
                }
                .padding()
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(radius: 2)

                // Reset Button
                Button(action: {
                    testViewModel.resetTest()
                }) {
                    Label("New Test", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.bottom)
            }
            .padding()
        }
    }

    // MARK: - Haptic Feedback
    private func setupHapticFeedback() {
        testViewModel.onPhaseTransition = { phase in
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(phase == .work ? .success : .warning)
        }
    }
}
