//
//  CriticalForceViewModel.swift
//  Limit
//
//  Critical Force test implementation based on Kellawan & Tschakovsky methodology
//

import Foundation
import Combine
import AVFoundation

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
}

class CriticalForceViewModel: ObservableObject {
    // Test configuration
    private let totalContractions = 24 // 4 minutes
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

    // Private state
    private var testStartTime: Date?
    private var phaseStartTime: Date?
    private var currentPhaseForceData: [(timestamp: TimeInterval, force: Double)] = []
    private var cancellables = Set<AnyCancellable>()
    private var timerCancellable: AnyCancellable?
    private var audioPlayer: AVAudioPlayer?

    // Callback for phase transitions (for haptic feedback)
    var onPhaseTransition: ((TestPhase) -> Void)?

    // MARK: - Computed Properties

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

    func startTest(forcePublisher: Published<Double>.Publisher) {
        resetTest()
        isTestActive = true
        testStartTime = Date()
        phaseStartTime = Date()
        currentPhase = .preparation
        currentContraction = 1
        phaseTimeRemaining = preparationDuration

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
        testStartTime = nil
        phaseStartTime = nil
        currentPhaseForceData = []
        timerCancellable?.cancel()
        cancellables.removeAll()
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
            currentPhaseForceData = []
            currentPeakForce = 0.0
            currentMeanForce = 0.0
            playBeep()
            onPhaseTransition?(.work)
        } else if currentPhase == .work {
            // Finish work phase - save contraction data
            saveContractionData()

            // Check if test is complete
            if currentContraction >= totalContractions {
                completeTest()
                return
            }

            // Transition to rest
            currentPhase = .rest
            phaseTimeRemaining = restDuration
            phaseStartTime = Date()
            currentPhaseForceData = []
            playBeep()
            onPhaseTransition?(.rest)
        } else {
            // Transition from rest to next work phase
            currentContraction += 1
            currentPhase = .work
            phaseTimeRemaining = workDuration
            phaseStartTime = Date()
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

        // Track force data for current phase
        if currentPhase == .work {
            let phaseElapsed = Date().timeIntervalSince(phaseStartTime ?? startTime)
            currentPhaseForceData.append((timestamp: phaseElapsed, force: force))

            // Update real-time metrics
            updateCurrentContractionMetrics()
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

    private func saveContractionData() {
        guard !currentPhaseForceData.isEmpty else { return }

        // Calculate metrics
        let peakForce = currentPhaseForceData.map { $0.force }.max() ?? 0.0
        let meanForce = currentPhaseForceData.map { $0.force }.reduce(0, +) / Double(currentPhaseForceData.count)

        // Calculate impulse (force-time integral) using trapezoidal rule
        var impulse = 0.0
        for i in 1..<currentPhaseForceData.count {
            let dt = currentPhaseForceData[i].timestamp - currentPhaseForceData[i-1].timestamp
            let avgForce = (currentPhaseForceData[i].force + currentPhaseForceData[i-1].force) / 2.0
            impulse += avgForce * dt
        }

        let startTime = currentPhaseForceData.first?.timestamp ?? 0.0
        let endTime = currentPhaseForceData.last?.timestamp ?? 0.0

        let contraction = ContractionData(
            contractionNumber: currentContraction,
            peakForce: peakForce,
            meanForce: meanForce,
            impulse: impulse,
            startTime: startTime,
            endTime: endTime
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

        let result = TestResult(from: contractions, criticalForce: cf, wPrime: wp)
        PersistenceManager.shared.save(result: result)
        print("✅ Saved test result: CF=\(cf), W'=\(wp)")
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
