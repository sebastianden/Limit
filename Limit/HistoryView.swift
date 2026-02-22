//
//  HistoryView.swift
//  Limit
//
//  View for displaying test history
//

import SwiftUI
import Charts

struct HistoryView: View {
    @ObservedObject var persistenceManager: PersistenceManager
    @State private var selectedResult: TestResult?
    @State private var exportItem: ExportItem?

    var body: some View {
        NavigationStack {
            Group {
                if persistenceManager.testResults.isEmpty {
                    emptyState
                } else {
                    resultsList
                }
            }
            .navigationTitle("Test History")
            .toolbar {
                if !persistenceManager.testResults.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Menu {
                            Button(role: .destructive, action: {
                                persistenceManager.deleteAll()
                            }) {
                                Label("Delete All", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .sheet(item: $selectedResult) { result in
                TestResultDetailView(result: result, persistenceManager: persistenceManager)
            }
            .sheet(item: $exportItem) { item in
                ShareSheet(items: [item.url])
            }
        }
    }

    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("No Test Results")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Complete a Critical Force test to see your results here")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Results List
    private var resultsList: some View {
        List {
            ForEach(persistenceManager.testResults) { result in
                ResultRow(result: result)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedResult = result
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            persistenceManager.delete(result: result)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }

                        Button {
                            exportResult(result)
                        } label: {
                            Label("Export", systemImage: "square.and.arrow.up")
                        }
                        .tint(.blue)
                    }
            }
        }
    }

    private func exportResult(_ result: TestResult) {
        if let url = persistenceManager.exportToCSV(result: result) {
            exportItem = ExportItem(url: url)
        }
    }
}

// MARK: - Result Row
struct ResultRow: View {
    let result: TestResult

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(result.formattedDate)
                .font(.headline)

            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Critical Force")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(String(format: "%.2f", result.criticalForce))
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(.green)

                        Text("kg")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("W'")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(String(format: "%.1f", result.wPrime))
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)

                        Text("kg·s")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(result.phases.count)")
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text("phases")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Test Result Detail View
struct TestResultDetailView: View {
    let result: TestResult
    let persistenceManager: PersistenceManager

    @Environment(\.dismiss) var dismiss
    @State private var exportItem: ExportItem?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Summary Cards
                    HStack(spacing: 16) {
                        summaryCard(title: "Critical Force", value: String(format: "%.2f", result.criticalForce), unit: "kg", color: .green)
                        summaryCard(title: "W'", value: String(format: "%.1f", result.wPrime), unit: "kg·s", color: .blue)
                    }

                    // Full Test Chart
                    fullTestChart(for: result)

                    // Phase Details
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Phase Details")
                            .font(.headline)

                        ForEach(result.phases) { phase in
                            PhaseDetailRow(phase: phase)
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(radius: 2)
                }
                .padding()
            }
            .navigationTitle(result.shortDate)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        exportResult()
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .sheet(item: $exportItem) { item in
                ShareSheet(items: [item.url])
            }
        }
    }

    private func summaryCard(title: String, value: String, unit: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(color)

                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func fullTestChart(for result: TestResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Complete Test Data")
                .font(.headline)

            let cf = result.criticalForce

            // Flatten all raw data with absolute timeline
            // Each phase starts at (phaseNumber-1) * 10s (7s work + 3s rest)
            let allDataPoints = result.phases.flatMap { phase -> [(time: Double, force: Double)] in
                let phaseStartTime = Double(phase.phaseNumber - 1) * 10.0
                return phase.rawReadings.map { reading in
                    (time: phaseStartTime + reading.timestamp, force: reading.force)
                }
            }

            // Calculate time domain
            let maxTime = allDataPoints.map { $0.time }.max() ?? 0

            Chart {
                // Plot raw force data
                ForEach(Array(allDataPoints.enumerated()), id: \.offset) { index, point in
                    LineMark(
                        x: .value("Time", point.time),
                        y: .value("Force", point.force)
                    )
                    .foregroundStyle(.blue)
                    .interpolationMethod(.stepEnd)
                }

                // Critical Force reference line
                if cf > 0 {
                    RuleMark(y: .value("Critical Force", cf))
                        .foregroundStyle(.green)
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 5]))
                        .annotation(position: .top, alignment: .trailing) {
                            Text("CF: \(String(format: "%.1f", cf)) kg")
                                .font(.caption)
                                .padding(4)
                                .background(Color.green.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                }
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
                            Text("\(Int(time))s")
                        }
                    }
                }
            }
            .chartXScale(domain: 0...max(maxTime, 1))
            .frame(height: 200)
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 2)
    }

    private func exportResult() {
        if let url = persistenceManager.exportToCSV(result: result) {
            exportItem = ExportItem(url: url)
        }
    }
}

// MARK: - Phase Detail Row
struct PhaseDetailRow: View {
    let phase: PhaseData

    var body: some View {
        HStack {
            Text("#\(phase.phaseNumber)")
                .font(.subheadline)
                .fontWeight(.semibold)
                .frame(width: 40, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text("Peak: \(String(format: "%.1f", phase.peakForce)) kg")
                    .font(.caption)
                Text("Mean: \(String(format: "%.1f", phase.meanForce)) kg")
                    .font(.caption)
            }

            Spacer()

            Text("\(String(format: "%.1f", phase.impulse)) kg·s")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Export Item
struct ExportItem: Identifiable {
    let id = UUID()
    let url: URL
}

// MARK: - Share Sheet
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No updates needed
    }
}

#Preview {
    HistoryView(persistenceManager: PersistenceManager.shared)
}
