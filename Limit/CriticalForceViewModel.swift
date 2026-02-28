//
//  CriticalForceViewModel.swift
//  Limit
//
//  Critical Force test implementation based on Kellawan & Tschakovsky methodology
//

import Foundation
import Combine
import AVFoundation
import UIKit

enum TestPhase {
    case preparation
    case work
    case rest
}

struct ContractionData: Identifiable {
    let id = UUID()
    let contractionNumber: Int
    let peakForce: Double
    let meanForce: Double
    let impulse: Double // force-time integral (kg·s)
    let startTime: TimeInterval
    let endTime: TimeInterval
    let rawData: [(timestamp: TimeInterval, force: Double)] // Raw force readings
}

class CriticalForceViewModel: ObservableObject {
    // Test configuration
    private let totalContractions = 6 // 6 phases = 1 minute total (7s work + 3s rest per phase) - FOR TESTING
    private let preparationDuration: TimeInterval = 10.0
    private let workDuration: TimeInterval = 7.0
    private let restDuration: TimeInterval = 3.0

    // Published state
    @Published var isTestActive = false
    @Published var currentPhase: TestPhase = .work
    @Published var currentContraction = 1
    @Published var phaseTimeRemaining: TimeInterval = 7.0
    @Published var currentForce: Double = 0.0
    @Published var dataPoints: [ForceDataPoint] = []

    // Current contraction metrics (updated in real-time during work phase)
    @Published var currentPeakForce: Double = 0.0
    @Published var currentMeanForce: Double = 0.0

    // Test results
    @Published var isTestCompleted = false
    @Published var criticalForce: Double? = nil
    @Published var currentCriticalForce: Double? = nil // Updated after each phase
    @Published var wPrime: Double? = nil
    @Published var contractions: [ContractionData] = []

    // Test configuration (set before test starts)
    @Published var testHand: Hand? = nil
    @Published var testBodyweight: Double? = nil

    // Private state
    private var testStartTime: Date?
    private var phaseStartTime: Date? // For phase timer display
    private var contractionStartTime: Date? // For contraction data timestamps (not reset during REST)
    private var currentPhaseForceData: [(timestamp: TimeInterval, force: Double)] = []
    private var cancellables = Set<AnyCancellable>()
    private var timerCancellable: AnyCancellable?
    private var audioPlayer: AVAudioPlayer?

    // Store work phase metrics separately (before including rest data)
    private var workPhasePeakForce: Double = 0.0
    private var workPhaseMeanForce: Double = 0.0
    private var workPhaseImpulse: Double = 0.0
    private var workPhaseStartTime: TimeInterval = 0.0
    private var workPhaseEndTime: TimeInterval = 0.0

    // Callback for phase transitions (for haptic feedback)
    var onPhaseTransition: ((TestPhase) -> Void)?

    // MARK: - Computed Properties

    var totalPhases: Int {
        return totalContractions
    }

    var progress: Double {
        if currentPhase == .preparation {
            return 0.0
        }
        let totalPhases = totalContractions * 2 // work + rest for each contraction
        let completedPhases = (currentContraction - 1) * 2 + (currentPhase == .rest ? 1 : 0)
        return Double(completedPhases) / Double(totalPhases)
    }

    var last10SecondsData: [ForceDataPoint] {
        guard let startTime = testStartTime else { return [] }
        let currentTime = Date().timeIntervalSince(startTime)
        let tenSecondsAgo = max(0, currentTime - 10)

        return dataPoints.filter { $0.timestamp >= tenSecondsAgo }
    }

    var xAxisRange: ClosedRange<Double> {
        guard let startTime = testStartTime else { return 0...10 }
        let currentTime = Date().timeIntervalSince(startTime)

        if currentTime <= 10 {
            return 0...10
        } else {
            let start = currentTime - 10
            let end = currentTime
            return start...end
        }
    }

    // MARK: - Test Control

    func startTest(forcePublisher: Published<Double>.Publisher, hand: Hand, bodyweight: Double) {
        resetTest()

        // Store test configuration
        testHand = hand
        testBodyweight = bodyweight

        isTestActive = true
        testStartTime = Date()
        phaseStartTime = Date()
        currentPhase = .preparation
        currentContraction = 1
        phaseTimeRemaining = preparationDuration

        // Disable idle timer to prevent screen from locking during test
        UIApplication.shared.isIdleTimerDisabled = true

        // Subscribe to force updates
        forcePublisher
            .sink { [weak self] force in
                self?.updateTest(with: force)
            }
            .store(in: &cancellables)

        // Start phase timer
        startPhaseTimer()

        // Play start beep
        playBeep()
        onPhaseTransition?(.preparation)
    }

    func stopTest() {
        isTestActive = false
        timerCancellable?.cancel()
        cancellables.removeAll()

        // Re-enable idle timer
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func resetTest() {
        isTestActive = false
        isTestCompleted = false
        currentPhase = .preparation
        currentContraction = 1
        phaseTimeRemaining = preparationDuration
        currentForce = 0.0
        currentPeakForce = 0.0
        currentMeanForce = 0.0
        dataPoints = []
        contractions = []
        criticalForce = nil
        currentCriticalForce = nil
        wPrime = nil
        testHand = nil
        testBodyweight = nil
        testStartTime = nil
        phaseStartTime = nil
        contractionStartTime = nil
        currentPhaseForceData = []
        workPhasePeakForce = 0.0
        workPhaseMeanForce = 0.0
        workPhaseImpulse = 0.0
        workPhaseStartTime = 0.0
        workPhaseEndTime = 0.0
        timerCancellable?.cancel()
        cancellables.removeAll()

        // Re-enable idle timer
        UIApplication.shared.isIdleTimerDisabled = false
    }

    // MARK: - Private Methods

    private func startPhaseTimer() {
        timerCancellable = Timer.publish(every: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updatePhaseTimer()
            }
    }

    private func updatePhaseTimer() {
        guard let phaseStart = phaseStartTime else { return }

        let elapsed = Date().timeIntervalSince(phaseStart)
        let phaseDuration: TimeInterval
        switch currentPhase {
        case .preparation:
            phaseDuration = preparationDuration
        case .work:
            phaseDuration = workDuration
        case .rest:
            phaseDuration = restDuration
        }
        phaseTimeRemaining = max(0, phaseDuration - elapsed)

        // Check if phase is complete
        if elapsed >= phaseDuration {
            transitionPhase()
        }
    }

    private func transitionPhase() {
        if currentPhase == .preparation {
            // Transition from preparation to first work phase
            currentPhase = .work
            phaseTimeRemaining = workDuration
            phaseStartTime = Date()
            contractionStartTime = Date() // Start timing the full contraction cycle
            currentPhaseForceData = []
            currentPeakForce = 0.0
            currentMeanForce = 0.0
            playBeep()
            onPhaseTransition?(.work)
        } else if currentPhase == .work {
            // Finish work phase - calculate and store work metrics (don't save contraction yet)
            calculateWorkPhaseMetrics()

            // Check if test is complete (after last work phase)
            if currentContraction >= totalContractions {
                // Save the last contraction (work phase only, no rest after)
                saveContractionData()
                completeTest()
                return
            }

            // Transition to rest (continue collecting data in currentPhaseForceData)
            currentPhase = .rest
            phaseTimeRemaining = restDuration
            phaseStartTime = Date() // For timer display only
            // NOTE: Don't reset contractionStartTime - timestamps continue from work phase
            // NOTE: Don't clear currentPhaseForceData - keep collecting through rest phase
            playBeep()
            onPhaseTransition?(.rest)
        } else {
            // Transition from rest to next work phase - now save the contraction with full data
            saveContractionData()

            // Move to next contraction
            currentContraction += 1
            currentPhase = .work
            phaseTimeRemaining = workDuration
            phaseStartTime = Date()
            contractionStartTime = Date() // Start timing the new contraction cycle
            currentPhaseForceData = []
            currentPeakForce = 0.0
            currentMeanForce = 0.0
            playBeep()
            onPhaseTransition?(.work)
        }
    }

    private func updateTest(with force: Double) {
        guard isTestActive, let startTime = testStartTime else { return }

        currentForce = force

        // Don't collect data during preparation phase
        if currentPhase == .preparation {
            return
        }

        // Add data point for chart
        let elapsed = Date().timeIntervalSince(startTime)
        let dataPoint = ForceDataPoint(timestamp: elapsed, force: force)
        dataPoints.append(dataPoint)

        // Keep only last 60 seconds for memory management
        if elapsed > 60 {
            dataPoints.removeAll { $0.timestamp < elapsed - 60 }
        }

        // Track force data for current phase (WORK and REST, but not PREPARATION)
        if currentPhase == .work || currentPhase == .rest {
            // Use contractionStartTime for continuous timestamps across work+rest
            let contractionElapsed = Date().timeIntervalSince(contractionStartTime ?? startTime)
            currentPhaseForceData.append((timestamp: contractionElapsed, force: force))

            // Update real-time metrics (only during work phase)
            if currentPhase == .work {
                updateCurrentContractionMetrics()
            }
        }
    }

    private func updateCurrentContractionMetrics() {
        guard !currentPhaseForceData.isEmpty else { return }

        // Peak force
        currentPeakForce = currentPhaseForceData.map { $0.force }.max() ?? 0.0

        // Mean force
        let sum = currentPhaseForceData.map { $0.force }.reduce(0, +)
        currentMeanForce = sum / Double(currentPhaseForceData.count)
    }

    private func calculateWorkPhaseMetrics() {
        guard !currentPhaseForceData.isEmpty else { return }

        // Calculate metrics from WORK phase only (before REST data is added)
        workPhasePeakForce = currentPhaseForceData.map { $0.force }.max() ?? 0.0
        workPhaseMeanForce = currentPhaseForceData.map { $0.force }.reduce(0, +) / Double(currentPhaseForceData.count)

        // Calculate impulse (force-time integral) using trapezoidal rule
        var impulse = 0.0
        for i in 1..<currentPhaseForceData.count {
            let dt = currentPhaseForceData[i].timestamp - currentPhaseForceData[i-1].timestamp
            let avgForce = (currentPhaseForceData[i].force + currentPhaseForceData[i-1].force) / 2.0
            impulse += avgForce * dt
        }
        workPhaseImpulse = impulse

        workPhaseStartTime = currentPhaseForceData.first?.timestamp ?? 0.0
        workPhaseEndTime = currentPhaseForceData.last?.timestamp ?? 0.0
    }

    private func saveContractionData() {
        guard !currentPhaseForceData.isEmpty else { return }

        // Use pre-calculated work phase metrics (stored from end of work phase)
        // But include full raw data (work + rest phases)
        let contraction = ContractionData(
            contractionNumber: currentContraction,
            peakForce: workPhasePeakForce,
            meanForce: workPhaseMeanForce,
            impulse: workPhaseImpulse,
            startTime: workPhaseStartTime,
            endTime: workPhaseEndTime,
            rawData: currentPhaseForceData // Includes both work and rest data
        )

        contractions.append(contraction)

        // Update current CF after each phase (if we have at least 6)
        updateCurrentCriticalForce()
    }

    private func updateCurrentCriticalForce() {
        guard contractions.count >= 6 else {
            currentCriticalForce = nil
            return
        }

        // Get last 6 contractions
        let lastSix = Array(contractions.suffix(6))
        let meanForces = lastSix.map { $0.meanForce }

        // Calculate mean and standard deviation
        let mean = meanForces.reduce(0, +) / Double(meanForces.count)
        let variance = meanForces.map { pow($0 - mean, 2) }.reduce(0, +) / Double(meanForces.count)
        let stdDev = sqrt(variance)

        // Filter out contractions outside 1 SD (to remove erroneous contractions)
        let filteredForces = meanForces.filter { abs($0 - mean) <= stdDev }

        // Current CF = mean of filtered end-test forces
        if !filteredForces.isEmpty {
            currentCriticalForce = filteredForces.reduce(0, +) / Double(filteredForces.count)
        } else {
            currentCriticalForce = mean // fallback if all filtered out
        }
    }

    private func completeTest() {
        isTestActive = false
        isTestCompleted = true
        timerCancellable?.cancel()
        cancellables.removeAll()

        // Re-enable idle timer
        UIApplication.shared.isIdleTimerDisabled = false

        // Calculate Critical Force and W'
        calculateResults()

        // Save results to persistence
        saveResults()

        // Play completion sound
        playCompletionSound()
    }

    private func saveResults() {
        guard let cf = criticalForce, let wp = wPrime else {
            print("⚠️ Cannot save results: CF or W' is nil")
            return
        }

        let result = TestResult(from: contractions, criticalForce: cf, wPrime: wp, hand: testHand, bodyweight: testBodyweight)
        PersistenceManager.shared.save(result: result)
        print("✅ Saved test result: CF=\(cf), W'=\(wp), Hand=\(testHand?.displayName ?? "nil"), BW=\(testBodyweight ?? 0)")
    }

    private func calculateResults() {
        guard contractions.count >= 6 else {
            print("Not enough contractions to calculate CF")
            return
        }

        // Get last 6 contractions
        let lastSix = Array(contractions.suffix(6))
        let meanForces = lastSix.map { $0.meanForce }

        // Calculate mean and standard deviation
        let mean = meanForces.reduce(0, +) / Double(meanForces.count)
        let variance = meanForces.map { pow($0 - mean, 2) }.reduce(0, +) / Double(meanForces.count)
        let stdDev = sqrt(variance)

        // Filter out contractions outside 1 SD (to remove erroneous contractions)
        let filteredForces = meanForces.filter { abs($0 - mean) <= stdDev }

        // Critical Force = mean of filtered end-test forces
        if !filteredForces.isEmpty {
            criticalForce = filteredForces.reduce(0, +) / Double(filteredForces.count)
        } else {
            criticalForce = mean // fallback if all filtered out
        }

        // Calculate W' (impulse above CF)
        if let cf = criticalForce {
            var totalWPrime = 0.0

            for contraction in contractions {
                // W' for this contraction = impulse above CF
                // Impulse above CF = (mean force - CF) * duration
                let duration = contraction.endTime - contraction.startTime
                let impulseAboveCF = max(0, (contraction.meanForce - cf) * duration)
                totalWPrime += impulseAboveCF
            }

            wPrime = totalWPrime
        }
    }

    // MARK: - Audio Feedback

    private func playBeep() {
        // Generate a short beep sound
        AudioServicesPlaySystemSound(1057) // Tink sound
    }

    private func playCompletionSound() {
        // Play a completion sound
        AudioServicesPlaySystemSound(1054) // Triple beep
    }
}
