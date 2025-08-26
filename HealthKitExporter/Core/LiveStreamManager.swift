//
//  LiveStreamManager.swift
//  HealthKitExporter
//
//  Background streaming engine for continuous health data generation
//

import Foundation
import HealthKit
import SwiftUI
import UIKit
import ActivityKit

@MainActor
class LiveStreamManager: ObservableObject {
    private let healthStore = HKHealthStore()
    private var streamingTimer: Timer?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var liveActivity: Activity<LiveStreamActivityAttributes>?
    
    @Published var isStreaming = false
    @Published var currentScenario: StreamingScenario = .normal
    @Published var streamingInterval: TimeInterval = 60 // seconds
    @Published var totalSamplesGenerated = 0
    @Published var lastGeneratedValues: [String: Double] = [:]
    @Published var streamingStatus = "Ready to stream"
    @Published var sourceBundle: ExportedHealthBundle?
    
    // Safety limits
    private let maxSamplesPerHour = 3600 // 1 per second max
    private let maxTotalSamples = 10000
    private var samplesGeneratedThisHour = 0
    private var hourlyResetTimer: Timer?
    
    // Current baseline values derived from source data
    private var baselineHeartRate: Double = 70
    private var baselineHRV: Double = 45
    private var currentSeed: Int = 0
    
    // MARK: - Streaming Control
    
    func startStreaming() {
        guard !isStreaming else { return }
        guard sourceBundle != nil else {
            streamingStatus = "No source data loaded"
            return
        }
        
        // Reset counters
        samplesGeneratedThisHour = 0
        totalSamplesGenerated = 0
        currentSeed = Int.random(in: 0...1000)
        
        // Calculate baselines from source data
        calculateBaselines()
        
        isStreaming = true
        streamingStatus = "Streaming \(currentScenario.rawValue)..."
        
        // Start Live Activity
        startLiveActivity()
        
        // Start background task for when app goes to background
        beginBackgroundTask()
        
        // Start streaming timer
        streamingTimer = Timer.scheduledTimer(withTimeInterval: streamingInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.generateAndStreamSample()
            }
        }
        
        // Start hourly reset timer
        hourlyResetTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.samplesGeneratedThisHour = 0
            }
        }
    }
    
    func stopStreaming() {
        guard isStreaming else { return }
        
        isStreaming = false
        streamingStatus = "Streaming stopped"
        
        streamingTimer?.invalidate()
        streamingTimer = nil
        
        hourlyResetTimer?.invalidate()
        hourlyResetTimer = nil
        
        // End Live Activity
        endLiveActivity()
        
        endBackgroundTask()
    }
    
    func pauseStreaming() {
        streamingTimer?.invalidate()
        streamingTimer = nil
        streamingStatus = "Paused"
    }
    
    func resumeStreaming() {
        guard isStreaming else { return }
        
        streamingTimer = Timer.scheduledTimer(withTimeInterval: streamingInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.generateAndStreamSample()
            }
        }
        streamingStatus = "Streaming \(currentScenario.rawValue)..."
    }
    
    // MARK: - Data Generation
    
    private func generateAndStreamSample() async {
        // Safety checks
        guard samplesGeneratedThisHour < maxSamplesPerHour else {
            streamingStatus = "Hourly limit reached, waiting..."
            return
        }
        
        guard totalSamplesGenerated < maxTotalSamples else {
            streamingStatus = "Total limit reached, stopping..."
            stopStreaming()
            return
        }
        
        do {
            let now = Date()
            let heartRateValue = generateHeartRate(at: now)
            let hrvValue = generateHRV(at: now)
            
            // Generate and save heart rate sample
            if let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) {
                let heartRateQuantity = HKQuantity(unit: HKUnit.count().unitDivided(by: .minute()), 
                                                 doubleValue: heartRateValue)
                let heartRateSample = HKQuantitySample(
                    type: heartRateType,
                    quantity: heartRateQuantity,
                    start: now,
                    end: now
                )
                
                try await saveSample(heartRateSample)
            }
            
            // Generate and save HRV sample
            if let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) {
                let hrvQuantity = HKQuantity(unit: HKUnit.secondUnit(with: .milli), 
                                           doubleValue: hrvValue)
                let hrvSample = HKQuantitySample(
                    type: hrvType,
                    quantity: hrvQuantity,
                    start: now,
                    end: now
                )
                
                try await saveSample(hrvSample)
            }
            
            // Update tracking
            samplesGeneratedThisHour += 2 // HR + HRV
            totalSamplesGenerated += 2
            lastGeneratedValues = [
                "Heart Rate": heartRateValue,
                "HRV": hrvValue
            ]
            
            streamingStatus = "Streaming (\(totalSamplesGenerated) samples)"
            
            // Update Live Activity
            updateLiveActivity()
            
        } catch {
            streamingStatus = "Error: \(error.localizedDescription)"
        }
    }
    
    private func generateHeartRate(at date: Date) -> Double {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        
        // Time-based baseline adjustment (circadian rhythm)
        let timeOfDay = Double(hour) + Double(minute) / 60.0
        let circadianAdjustment = generateCircadianAdjustment(timeOfDay: timeOfDay)
        
        let adjustedBaseline = baselineHeartRate + circadianAdjustment
        
        // Apply scenario-specific modifications
        return currentScenario.applyToHeartRate(
            baseline: adjustedBaseline,
            timeOfDay: timeOfDay,
            seed: currentSeed + totalSamplesGenerated
        )
    }
    
    private func generateHRV(at date: Date) -> Double {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        
        let timeOfDay = Double(hour) + Double(minute) / 60.0
        let circadianAdjustment = generateHRVCircadianAdjustment(timeOfDay: timeOfDay)
        
        let adjustedBaseline = baselineHRV + circadianAdjustment
        
        return currentScenario.applyToHRV(
            baseline: adjustedBaseline,
            timeOfDay: timeOfDay,
            seed: currentSeed + totalSamplesGenerated
        )
    }
    
    private func generateCircadianAdjustment(timeOfDay: Double) -> Double {
        // Lower HR during sleep hours (22:00 - 6:00), higher during active hours
        let sleepHours = timeOfDay >= 22 || timeOfDay <= 6
        let peakHours = timeOfDay >= 9 && timeOfDay <= 18
        
        if sleepHours {
            return -15 + cos(timeOfDay * .pi / 12) * 5 // Lower, with variation
        } else if peakHours {
            return 10 + sin(timeOfDay * .pi / 12) * 8 // Higher, with variation
        } else {
            return cos(timeOfDay * .pi / 12) * 5 // Moderate variation
        }
    }
    
    private func generateHRVCircadianAdjustment(timeOfDay: Double) -> Double {
        // Higher HRV during sleep (better recovery), lower during stress hours
        let sleepHours = timeOfDay >= 22 || timeOfDay <= 6
        let stressHours = timeOfDay >= 9 && timeOfDay <= 17
        
        if sleepHours {
            return 15 + sin(timeOfDay * .pi / 12) * 8 // Higher HRV during sleep
        } else if stressHours {
            return -10 + cos(timeOfDay * .pi / 8) * 5 // Lower HRV during work hours
        } else {
            return sin(timeOfDay * .pi / 12) * 5 // Moderate variation
        }
    }
    
    // MARK: - Background Task Management
    
    private func beginBackgroundTask() {
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "HealthDataStreaming") { [weak self] in
            self?.endBackgroundTask()
        }
    }
    
    private func endBackgroundTask() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }
    
    // MARK: - Helper Methods
    
    private func calculateBaselines() {
        guard let bundle = sourceBundle else { return }
        
        if !bundle.heartRate.isEmpty {
            baselineHeartRate = bundle.heartRate.map(\.value).reduce(0, +) / Double(bundle.heartRate.count)
        }
        
        if !bundle.hrv.isEmpty {
            baselineHRV = bundle.hrv.map(\.value).reduce(0, +) / Double(bundle.hrv.count)
        }
    }
    
    private func saveSample(_ sample: HKSample) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.save(sample) { success, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
    
    // MARK: - Live Activity Management
    
    private func startLiveActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        
        let attributes = LiveStreamActivityAttributes(
            startTime: Date(),
            interval: streamingInterval
        )
        
        let initialState = LiveStreamActivityAttributes.ContentState(
            isStreaming: true,
            scenario: currentScenario.rawValue,
            totalSamples: totalSamplesGenerated,
            lastHeartRate: nil,
            lastHRV: nil,
            streamingStatus: streamingStatus,
            lastUpdateTime: Date()
        )
        
        do {
            liveActivity = try Activity<LiveStreamActivityAttributes>.request(
                attributes: attributes,
                contentState: initialState,
                pushType: nil
            )
        } catch {
            print("Failed to start Live Activity: \(error)")
        }
    }
    
    private func updateLiveActivity() {
        guard let liveActivity = liveActivity else { return }
        
        Task {
            let updatedState = LiveStreamActivityAttributes.ContentState(
                isStreaming: isStreaming,
                scenario: currentScenario.rawValue,
                totalSamples: totalSamplesGenerated,
                lastHeartRate: lastGeneratedValues["Heart Rate"],
                lastHRV: lastGeneratedValues["HRV"],
                streamingStatus: streamingStatus,
                lastUpdateTime: Date()
            )
            
            await liveActivity.update(using: updatedState)
        }
    }
    
    private func endLiveActivity() {
        guard let liveActivity = liveActivity else { return }
        
        Task {
            let finalState = LiveStreamActivityAttributes.ContentState(
                isStreaming: false,
                scenario: currentScenario.rawValue,
                totalSamples: totalSamplesGenerated,
                lastHeartRate: lastGeneratedValues["Heart Rate"],
                lastHRV: lastGeneratedValues["HRV"],
                streamingStatus: "Stopped",
                lastUpdateTime: Date()
            )
            
            await liveActivity.end(using: finalState, dismissalPolicy: .default)
            self.liveActivity = nil
        }
    }
    
    deinit {
        // Clean up without capturing self
        streamingTimer?.invalidate()
        hourlyResetTimer?.invalidate()
        
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
        }
        
        // End live activity without capturing self
        if let activity = liveActivity {
            Task {
                await activity.end(using: LiveStreamActivityAttributes.ContentState(
                    isStreaming: false,
                    scenario: "Stopped",
                    totalSamples: 0,
                    lastHeartRate: nil,
                    lastHRV: nil,
                    streamingStatus: "App closing",
                    lastUpdateTime: Date()
                ), dismissalPolicy: .immediate)
            }
        }
    }
}

// MARK: - Streaming Scenarios

enum StreamingScenario: String, CaseIterable {
    case normal = "Normal patterns"
    case stress = "Stress scenario" 
    case extreme = "Extreme events"
    case edgeCases = "Edge cases"
    case workout = "Workout simulation"
    case sleep = "Sleep patterns"
    
    var description: String {
        switch self {
        case .normal:
            return "Realistic daily variations with circadian rhythms"
        case .stress:
            return "Elevated heart rate, reduced HRV, simulating stress"
        case .extreme:
            return "Very high/low values, rapid changes, testing limits"
        case .edgeCases:
            return "Missing data, irregular intervals, corrupted patterns"
        case .workout:
            return "Simulate workout periods with elevated metrics"
        case .sleep:
            return "Simulate sleep patterns with recovery metrics"
        }
    }
    
    func applyToHeartRate(baseline: Double, timeOfDay: Double, seed: Int) -> Double {
        var rng = SeededRandomGenerator(seed: seed)
        
        switch self {
        case .normal:
            let variation = Double.random(in: -5...5, using: &rng)
            return max(40, min(180, baseline + variation))
            
        case .stress:
            let stressIncrease = Double.random(in: 15...35, using: &rng)
            let variation = Double.random(in: -3...8, using: &rng)
            return max(60, min(200, baseline + stressIncrease + variation))
            
        case .extreme:
            let extremeVariation = Double.random(in: -40...60, using: &rng)
            return max(30, min(220, baseline + extremeVariation))
            
        case .edgeCases:
            // Sometimes return edge values
            let isEdgeCase = Double.random(in: 0...1, using: &rng) < 0.3
            if isEdgeCase {
                return [35, 45, 180, 200, 220].randomElement(using: &rng) ?? baseline
            } else {
                let variation = Double.random(in: -10...10, using: &rng)
                return max(40, min(180, baseline + variation))
            }
            
        case .workout:
            // Simulate workout intensity
            let workoutIncrease = Double.random(in: 30...70, using: &rng)
            let variation = Double.random(in: -5...15, using: &rng)
            return max(80, min(200, baseline + workoutIncrease + variation))
            
        case .sleep:
            // Lower heart rate during sleep simulation
            let sleepDecrease = Double.random(in: 10...25, using: &rng)
            let variation = Double.random(in: -3...3, using: &rng)
            return max(40, min(90, baseline - sleepDecrease + variation))
        }
    }
    
    func applyToHRV(baseline: Double, timeOfDay: Double, seed: Int) -> Double {
        var rng = SeededRandomGenerator(seed: seed)
        
        switch self {
        case .normal:
            let variation = Double.random(in: -8...8, using: &rng)
            return max(10, min(100, baseline + variation))
            
        case .stress:
            // Lower HRV indicates stress
            let stressReduction = Double.random(in: 10...25, using: &rng)
            let variation = Double.random(in: -5...2, using: &rng)
            return max(10, min(80, baseline - stressReduction + variation))
            
        case .extreme:
            let extremeVariation = Double.random(in: -30...40, using: &rng)
            return max(5, min(120, baseline + extremeVariation))
            
        case .edgeCases:
            let isEdgeCase = Double.random(in: 0...1, using: &rng) < 0.3
            if isEdgeCase {
                return [5, 8, 95, 110, 150].randomElement(using: &rng) ?? baseline
            } else {
                let variation = Double.random(in: -12...12, using: &rng)
                return max(10, min(100, baseline + variation))
            }
            
        case .workout:
            // Lower HRV during intense exercise
            let workoutReduction = Double.random(in: 15...30, using: &rng)
            let variation = Double.random(in: -5...5, using: &rng)
            return max(8, min(60, baseline - workoutReduction + variation))
            
        case .sleep:
            // Higher HRV during good sleep/recovery
            let sleepIncrease = Double.random(in: 10...25, using: &rng)
            let variation = Double.random(in: -3...8, using: &rng)
            return max(15, min(120, baseline + sleepIncrease + variation))
        }
    }
}