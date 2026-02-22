//
//  TestResult.swift
//  Limit
//
//  Data model for storing and exporting test results
//

import Foundation

// MARK: - Test Result Model
struct TestResult: Codable, Identifiable {
    let id: UUID
    let date: Date
    let criticalForce: Double
    let wPrime: Double
    let phases: [PhaseData]

    init(id: UUID = UUID(), date: Date = Date(), criticalForce: Double, wPrime: Double, phases: [PhaseData]) {
        self.id = id
        self.date = date
        self.criticalForce = criticalForce
        self.wPrime = wPrime
        self.phases = phases
    }

    // Convert from ContractionData
    init(from contractions: [ContractionData], criticalForce: Double, wPrime: Double) {
        self.id = UUID()
        self.date = Date()
        self.criticalForce = criticalForce
        self.wPrime = wPrime
        self.phases = contractions.map { PhaseData(from: $0) }
    }
}

// MARK: - Phase Data Model
struct PhaseData: Codable, Identifiable {
    let id: UUID
    let phaseNumber: Int
    let peakForce: Double
    let meanForce: Double
    let impulse: Double
    let duration: Double

    init(id: UUID = UUID(), phaseNumber: Int, peakForce: Double, meanForce: Double, impulse: Double, duration: Double) {
        self.id = id
        self.phaseNumber = phaseNumber
        self.peakForce = peakForce
        self.meanForce = meanForce
        self.impulse = impulse
        self.duration = duration
    }

    // Convert from ContractionData
    init(from contraction: ContractionData) {
        self.id = UUID()
        self.phaseNumber = contraction.contractionNumber
        self.peakForce = contraction.peakForce
        self.meanForce = contraction.meanForce
        self.impulse = contraction.impulse
        self.duration = contraction.endTime - contraction.startTime
    }
}

// MARK: - CSV Export Extension
extension TestResult {
    func toCSV() -> String {
        var csv = "Critical Force Test Results\n"
        csv += "Date: \(formatDate(date))\n"
        csv += "Critical Force (CF): \(String(format: "%.2f", criticalForce)) kg\n"
        csv += "W' (W-Prime): \(String(format: "%.1f", wPrime)) kg·s\n"
        csv += "\n"
        csv += "Phase,Peak Force (kg),Mean Force (kg),Impulse (kg·s),Duration (s)\n"

        for phase in phases {
            csv += "\(phase.phaseNumber),"
            csv += "\(String(format: "%.2f", phase.peakForce)),"
            csv += "\(String(format: "%.2f", phase.meanForce)),"
            csv += "\(String(format: "%.2f", phase.impulse)),"
            csv += "\(String(format: "%.2f", phase.duration))\n"
        }

        return csv
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Display Formatting Extension
extension TestResult {
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    var shortDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
