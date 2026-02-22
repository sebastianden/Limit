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
        
        forcePublisher
            .sink { [weak self] force in
                self?.updateTest(with: force)
            }
            .store(in: &cancellables)
    }
    
    func stopTest() {
        isTestActive = false
        cancellables.removeAll()
    }
    
    func resetTest() {
        maxForce = 0.0
        dataPoints = []
        currentForce = 0.0
        testStartTime = nil
    }
    
    private func updateTest(with force: Double) {
        guard isTestActive, let startTime = testStartTime else { return }
        
        currentForce = force
        
        // Update max force
        if force > maxForce {
            maxForce = force
        }
        
        // Add data point
        let elapsed = Date().timeIntervalSince(startTime)
        let dataPoint = ForceDataPoint(timestamp: elapsed, force: force)
        dataPoints.append(dataPoint)
        
        // Keep only last 60 seconds of data for memory management
        // (even though we only display 10)
        if elapsed > 60 {
            dataPoints.removeAll { $0.timestamp < elapsed - 60 }
        }
    }
}
