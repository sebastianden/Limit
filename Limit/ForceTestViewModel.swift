//
//  ForceTestViewModel.swift
//  Limit
//
//  Created by STDG (Sebastian Dengler) on 22.02.26.
//

import Foundation
import Combine

struct ForceDataPoint: Identifiable {
    let id = UUID()
    let timestamp: TimeInterval
    let force: Double
}

class ForceTestViewModel: ObservableObject {
    @Published var isTestActive = false
    @Published var maxForce: Double = 0.0
    @Published var dataPoints: [ForceDataPoint] = []
    @Published var currentForce: Double = 0.0

    private var testStartTime: Date?
    private var cancellables = Set<AnyCancellable>()

    // DisplayLink for synchronized chart updates (performance optimization)
    private var displayLink: DisplayLink?
    private var pendingChartDataPoints: [ForceDataPoint] = []
    private let chartUpdateLock = NSLock()
    
    // Computed property to get last 10 seconds of data
    var last10SecondsData: [ForceDataPoint] {
        guard let startTime = testStartTime else { return [] }
        let currentTime = Date().timeIntervalSince(startTime)
        let tenSecondsAgo = max(0, currentTime - 10)
        
        return dataPoints.filter { $0.timestamp >= tenSecondsAgo }
    }
    
    // Computed property for X-axis range (always show 10 seconds)
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
    
    func startTest(forcePublisher: Published<Double>.Publisher) {
        isTestActive = true
        maxForce = 0.0
        dataPoints = []
        testStartTime = Date()

        // Start DisplayLink for synchronized chart updates (60Hz cap)
        startDisplayLink()

        forcePublisher
            .sink { [weak self] force in
                self?.updateTest(with: force)
            }
            .store(in: &cancellables)
    }

    func stopTest() {
        isTestActive = false
        cancellables.removeAll()

        // Stop DisplayLink
        stopDisplayLink()
    }

    func resetTest() {
        maxForce = 0.0
        dataPoints = []
        currentForce = 0.0
        testStartTime = nil

        // Clear DisplayLink buffer
        chartUpdateLock.lock()
        pendingChartDataPoints.removeAll()
        chartUpdateLock.unlock()
    }
    
    private func updateTest(with force: Double) {
        guard isTestActive, let startTime = testStartTime else { return }

        currentForce = force

        // Update max force
        if force > maxForce {
            maxForce = force
        }

        // Buffer data point for chart (DisplayLink will flush at screen refresh rate)
        let elapsed = Date().timeIntervalSince(startTime)
        let dataPoint = ForceDataPoint(timestamp: elapsed, force: force)

        chartUpdateLock.lock()
        pendingChartDataPoints.append(dataPoint)
        chartUpdateLock.unlock()
    }

    // MARK: - DisplayLink Management (Performance Optimization)

    private func startDisplayLink() {
        displayLink = DisplayLink()
        displayLink?.start { [weak self] in
            self?.flushChartData()
        }
    }

    private func stopDisplayLink() {
        displayLink?.stop()
        displayLink = nil
    }

    private func flushChartData() {
        // Move pending data points to published array (synchronized with screen refresh)
        chartUpdateLock.lock()
        defer { chartUpdateLock.unlock() }

        guard !pendingChartDataPoints.isEmpty else { return }

        // Append all pending points
        dataPoints.append(contentsOf: pendingChartDataPoints)
        pendingChartDataPoints.removeAll()

        // Keep only last 60 seconds for memory management
        // Only trim every 100 readings to avoid O(n) operation on every update
        if dataPoints.count % 100 == 0 {
            guard let startTime = testStartTime else { return }
            let elapsed = Date().timeIntervalSince(startTime)

            if elapsed > 60 {
                let cutoffTime = elapsed - 60
                if let firstValidIndex = dataPoints.firstIndex(where: { $0.timestamp >= cutoffTime }) {
                    dataPoints.removeFirst(firstValidIndex)
                }
            }
        }
    }
}
