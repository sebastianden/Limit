//
//  TestResult.swift
//  Limit
//
//  Data model for storing and exporting test results
//

import Foundation

// MARK: - Hand Enum
enum Hand: String, Codable, CaseIterable {
    case left = "Left"
    case right = "Right"

    var displayName: String { rawValue }
    var icon: String {
        switch self {
        case .left: return "l.square.fill"
        case .right: return "r.square.fill"
        }
    }
}

// MARK: - Test Result Model
struct TestResult: Codable, Identifiable {
    let id: UUID
    let date: Date
    let criticalForce: Double
    let wPrime: Double
    let phases: [PhaseData]
    let hand: Hand?
    let bodyweight: Double?

    init(id: UUID = UUID(), date: Date = Date(), criticalForce: Double, wPrime: Double, phases: [PhaseData], hand: Hand? = nil, bodyweight: Double? = nil) {
        self.id = id
        self.date = date
        self.criticalForce = criticalForce
        self.wPrime = wPrime
        self.phases = phases
        self.hand = hand
        self.bodyweight = bodyweight
    }

    // Convert from ContractionData
    init(from contractions: [ContractionData], criticalForce: Double, wPrime: Double, hand: Hand? = nil, bodyweight: Double? = nil) {
        self.id = UUID()
        self.date = Date()
        self.criticalForce = criticalForce
        self.wPrime = wPrime
        self.phases = contractions.map { PhaseData(from: $0) }
        self.hand = hand
        self.bodyweight = bodyweight
    }
}

// MARK: - Raw Force Reading
struct RawForceReading: Codable {
    let timestamp: Double
    let force: Double
}

// MARK: - Phase Data Model
struct PhaseData: Codable, Identifiable {
    let id: UUID
    let phaseNumber: Int
    let peakForce: Double
    let meanForce: Double
    let impulse: Double
    let duration: Double
    let rawReadings: [RawForceReading]

    init(id: UUID = UUID(), phaseNumber: Int, peakForce: Double, meanForce: Double, impulse: Double, duration: Double, rawReadings: [RawForceReading] = []) {
        self.id = id
        self.phaseNumber = phaseNumber
        self.peakForce = peakForce
        self.meanForce = meanForce
        self.impulse = impulse
        self.duration = duration
        self.rawReadings = rawReadings
    }

    // Convert from ContractionData
    init(from contraction: ContractionData) {
        self.id = UUID()
        self.phaseNumber = contraction.contractionNumber
        self.peakForce = contraction.peakForce
        self.meanForce = contraction.meanForce
        self.impulse = contraction.impulse
        self.duration = contraction.endTime - contraction.startTime
        self.rawReadings = contraction.rawData.map { RawForceReading(timestamp: $0.timestamp, force: $0.force) }
    }
}

// MARK: - CSV Export Extension
extension TestResult {
    func toCSV() -> String {
        var csv = "Critical Force Test Results\n"
        csv += "Date: \(formatDate(date))\n"

        // Add hand and bodyweight if available
        if let hand = hand {
            csv += "Hand: \(hand.displayName)\n"
        }
        if let bodyweight = bodyweight {
            csv += "Bodyweight: \(String(format: "%.1f", bodyweight)) kg\n"
        }

        csv += "Critical Force (CF): \(String(format: "%.2f", criticalForce)) kg\n"
        csv += "W' (W-Prime): \(String(format: "%.1f", wPrime)) kg·s\n"

        // Add relative values if bodyweight available
        if let bodyweight = bodyweight, bodyweight > 0 {
            csv += "CF/kg: \(String(format: "%.1f", (criticalForce / bodyweight) * 100))%\n"
            csv += "W'/kg: \(String(format: "%.1f", (wPrime / bodyweight) * 100))%\n"
        }

        csv += "\n"

        // SECTION 1: Phase Summary Statistics
        csv += "=== PHASE SUMMARY ===\n"
        csv += "Phase,Peak Force (kg),Mean Force (kg),Impulse (kg·s),Duration (s)\n"

        for phase in phases {
            csv += "\(phase.phaseNumber),"
            csv += "\(String(format: "%.2f", phase.peakForce)),"
            csv += "\(String(format: "%.2f", phase.meanForce)),"
            csv += "\(String(format: "%.2f", phase.impulse)),"
            csv += "\(String(format: "%.2f", phase.duration))\n"
        }

        // SECTION 2: Raw Force Data
        csv += "\n=== RAW FORCE DATA ===\n"
        csv += "Phase,Time (s),Force (kg)\n"

        for phase in phases {
            for reading in phase.rawReadings {
                csv += "\(phase.phaseNumber),"
                csv += "\(String(format: "%.3f", reading.timestamp)),"
                csv += "\(String(format: "%.2f", reading.force))\n"
            }
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
