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
import AVFoundation
import CoreLocation
import BackgroundTasks

@MainActor
class LiveStreamManager: ObservableObject {
    private let healthStore = HKHealthStore()
    private var streamingTimer: Timer?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var secondaryBackgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var liveActivity: Activity<LiveStreamActivityAttributes>?
    
    // Aggressive background processing components
    private var audioPlayer: AVAudioPlayer?
    private let locationManager = CLLocationManager()
    private var backgroundTaskQueue: [UIBackgroundTaskIdentifier] = []
    private var keepAliveTimer: Timer?
    
    @Published var isStreaming = false
    @Published var currentScenario: StreamingScenario = .normal
    @Published var streamingInterval: TimeInterval = 60 // seconds
    @Published var totalSamplesGenerated = 0
    @Published var lastGeneratedValues: [String: Double] = [:]
    @Published var streamingStatus = "Ready to stream"
    @Published var detailedStatus = "Waiting for streaming to start"
    @Published var backgroundProcessingActive = false
    @Published var sourceBundle: ExportedHealthBundle?
    
    // Network streaming
    @MainActor private lazy var networkManager = NetworkStreamingManager()
    
    // Safety limits
    private let maxSamplesPerHour = 3600 // 1 per second max
    private let maxTotalSamples = 10000
    private var samplesGeneratedThisHour = 0
    private var hourlyResetTimer: Timer?
    
    // Current baseline values derived from source data
    private var baselineHeartRate: Double = 70
    private var baselineHRV: Double = 45
    private var currentSeed: Int = 0
    
    var networkStreamingManager: NetworkStreamingManager {
        networkManager
    }
    
    init() {
        Task { @MainActor in
            setupAggressiveBackgroundProcessing()
        }
    }
    
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
        detailedStatus = "Initializing streaming engine..."
        backgroundProcessingActive = true
        
        // Start Live Activity
        startLiveActivity()
        
        // Start background task for when app goes to background
        beginBackgroundTask()
        
        // Auto-start network broadcasting on device
        #if !targetEnvironment(simulator)
        if !networkManager.isServerRunning {
            networkManager.startServer()
        }
        #endif
        
        detailedStatus = "Background processing enabled, streaming active"
        
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
        detailedStatus = "Stopping background processing..."
        backgroundProcessingActive = false
        
        streamingTimer?.invalidate()
        streamingTimer = nil
        
        hourlyResetTimer?.invalidate()
        hourlyResetTimer = nil
        
        // End Live Activity
        endLiveActivity()
        
        // Auto-stop network broadcasting on device if no manual network streaming
        #if !targetEnvironment(simulator)
        if networkManager.isServerRunning {
            networkManager.stopServer()
        }
        #endif
        
        // Disable aggressive background processing
        disableAggressiveBackgroundProcessing()
        
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
    
    // MARK: - Network Streaming Control
    
    func startNetworkStreaming() {
        // Enable background processing for network streaming
        if !backgroundProcessingActive {
            backgroundProcessingActive = true
            beginBackgroundTask()
        }
        networkManager.startServer()
    }
    
    func stopNetworkStreaming() {
        networkManager.stopServer()
        // Keep background processing if live streaming is still active
        if !isStreaming {
            backgroundProcessingActive = false
            disableAggressiveBackgroundProcessing()
            endBackgroundTask()
        }
    }
    
    func startReceivingNetworkStream() {
        // Enable background processing for network receiving
        if !backgroundProcessingActive {
            backgroundProcessingActive = true
            beginBackgroundTask()
        }
        networkManager.startDiscovery()
    }
    
    func stopReceivingNetworkStream() {
        networkManager.stopDiscovery()
        networkManager.disconnect()
        // Keep background processing if live streaming is still active
        if !isStreaming {
            backgroundProcessingActive = false
            disableAggressiveBackgroundProcessing()
            endBackgroundTask()
        }
    }
    
    // MARK: - Data Generation
    
    internal func generateAndStreamSample() async {
        // Safety checks
        guard samplesGeneratedThisHour < maxSamplesPerHour else {
            streamingStatus = "Hourly limit reached, waiting..."
            detailedStatus = "Rate limited: \(samplesGeneratedThisHour)/\(maxSamplesPerHour) samples this hour"
            return
        }
        
        guard totalSamplesGenerated < maxTotalSamples else {
            streamingStatus = "Total limit reached, stopping..."
            detailedStatus = "Maximum samples reached: \(totalSamplesGenerated)/\(maxTotalSamples)"
            stopStreaming()
            return
        }
        
        detailedStatus = "Generating sample \(totalSamplesGenerated + 1)..."
        
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
            
            // Send data over network if connected
            let healthPacket = HealthDataPacket(
                timestamp: now,
                heartRate: heartRateValue,
                hrv: hrvValue,
                scenario: currentScenario.rawValue
            )
            networkManager.sendHealthData(healthPacket)
            
            let elapsed = Date().timeIntervalSince(backgroundTaskQueue.isEmpty ? Date() : Date().addingTimeInterval(-30))
            let rate = totalSamplesGenerated > 0 ? Double(totalSamplesGenerated) / max(elapsed / 60, 1) : 0
            
            streamingStatus = "Streaming (\(totalSamplesGenerated) samples)"
            detailedStatus = "Active: \(String(format: "%.1f", rate)) samples/min, Background: \(backgroundProcessingActive ? "ON" : "OFF")"
            
            // Update Live Activity
            updateLiveActivity()
            
        } catch {
            streamingStatus = "Error: \(error.localizedDescription)"
            detailedStatus = "Error generating sample: \(error.localizedDescription)"
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
        
        // Start secondary background task as backup
        secondaryBackgroundTask = UIApplication.shared.beginBackgroundTask(withName: "HealthDataStreamingBackup") { [weak self] in
            self?.endSecondaryBackgroundTask()
        }
        
        // Start aggressive background processing
        enableAggressiveBackgroundProcessing()
    }
    
    private func endBackgroundTask() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }
    
    private func endSecondaryBackgroundTask() {
        if secondaryBackgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(secondaryBackgroundTask)
            secondaryBackgroundTask = .invalid
        }
    }
    
    // MARK: - Aggressive Background Processing
    
    private func setupAggressiveBackgroundProcessing() {
        setupSilentAudio()
        setupLocationMonitoring()
        Task {
            await scheduleBackgroundAppRefresh()
        }
    }
    
    private func setupSilentAudio() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, 
                                       mode: .default, 
                                       options: [.mixWithOthers, .allowBluetooth])
            try audioSession.setActive(true)
            
            // Create silent audio file URL (we'll create a 1-second silent audio loop)
            guard let silentAudioURL = createSilentAudioFile() else {
                print("Failed to create silent audio file")
                return
            }
            
            audioPlayer = try AVAudioPlayer(contentsOf: silentAudioURL)
            audioPlayer?.numberOfLoops = -1 // Infinite loop
            audioPlayer?.volume = 0.005 // Very quiet but not silent
            
        } catch {
            print("Failed to setup silent audio: \(error)")
        }
    }
    
    private func createSilentAudioFile() -> URL? {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let audioURL = documentsPath.appendingPathComponent("silent.wav")
        
        // If file already exists, return it
        if FileManager.default.fileExists(atPath: audioURL.path) {
            return audioURL
        }
        
        // Create a 1-second WAV file with minimal audio data
        let sampleRate = 44100.0
        let duration = 1.0
        let samples = Int(sampleRate * duration)
        
        var audioData = Data()
        
        // WAV header
        audioData.append("RIFF".data(using: .ascii)!)
        audioData.append(withUnsafeBytes(of: UInt32(36 + samples * 2).littleEndian) { Data($0) })
        audioData.append("WAVE".data(using: .ascii)!)
        audioData.append("fmt ".data(using: .ascii)!)
        audioData.append(withUnsafeBytes(of: UInt32(16).littleEndian) { Data($0) }) // Subchunk1Size
        audioData.append(withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) })  // AudioFormat (PCM)
        audioData.append(withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) })  // NumChannels
        audioData.append(withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Data($0) }) // SampleRate
        audioData.append(withUnsafeBytes(of: UInt32(sampleRate * 2).littleEndian) { Data($0) }) // ByteRate
        audioData.append(withUnsafeBytes(of: UInt16(2).littleEndian) { Data($0) })  // BlockAlign
        audioData.append(withUnsafeBytes(of: UInt16(16).littleEndian) { Data($0) }) // BitsPerSample
        audioData.append("data".data(using: .ascii)!)
        audioData.append(withUnsafeBytes(of: UInt32(samples * 2).littleEndian) { Data($0) })
        
        // Audio data (very quiet sine wave to avoid complete silence)
        for i in 0..<samples {
            let amplitude = Int16(10) // Very quiet
            let sample = Int16(sin(Double(i) * 2.0 * .pi * 440.0 / sampleRate) * Double(amplitude))
            audioData.append(withUnsafeBytes(of: sample.littleEndian) { Data($0) })
        }
        
        do {
            try audioData.write(to: audioURL)
            return audioURL
        } catch {
            print("Failed to write silent audio file: \(error)")
            return nil
        }
    }
    
    private func setupLocationMonitoring() {
        locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers // Very coarse
        locationManager.distanceFilter = 1000 // 1km
        
        // Request always authorization for background location
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestAlwaysAuthorization()
        }
        
        // Enable significant location changes (very low power)
        if CLLocationManager.significantLocationChangeMonitoringAvailable() {
            locationManager.startMonitoringSignificantLocationChanges()
        }
    }
    
    private func scheduleBackgroundAppRefresh() async {
        // Skip scheduling when app is being debugged
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != nil ||
           ProcessInfo.processInfo.arguments.contains("-NSDocumentRevisionsDebugMode") {
            return
        }
        #endif
        
        let request = BGAppRefreshTaskRequest(identifier: "com.healthkitexporter.datastreaming")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30) // Try to run every 30 seconds
        
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Don't log errors in debug mode as BGTaskScheduler doesn't work when debugging
            #if !DEBUG
            print("Failed to schedule background app refresh: \(error)")
            #endif
        }
    }
    
    private func enableAggressiveBackgroundProcessing() {
        // Start silent audio playback
        audioPlayer?.play()
        
        // Create multiple overlapping background tasks
        createMultipleBackgroundTasks()
        
        // Start keep-alive timer
        startKeepAliveTimer()
    }
    
    private func createMultipleBackgroundTasks() {
        // Simplified background task management - only create one additional task
        var taskId: UIBackgroundTaskIdentifier = .invalid
        taskId = UIApplication.shared.beginBackgroundTask(withName: "HealthDataProcessing") {
            Task { @MainActor [weak self] in
                // Properly end the task when it expires
                if let index = self?.backgroundTaskQueue.firstIndex(of: taskId) {
                    self?.backgroundTaskQueue.remove(at: index)
                }
                UIApplication.shared.endBackgroundTask(taskId)
                print("🕐 Background task expired and ended")
            }
        }
        
        if taskId != .invalid {
            backgroundTaskQueue.append(taskId)
            print("✅ Created background task: \(taskId)")
        }
    }
    
    private func startKeepAliveTimer() {
        // Only keep silent audio playing for background processing
        // Skip complex background task management while debugging
        keepAliveTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                // Just keep the audio player active
                if let audioPlayer = self?.audioPlayer, !audioPlayer.isPlaying {
                    audioPlayer.play()
                    print("🔊 Restarted silent audio for background processing")
                }
            }
        }
    }
    
    private func disableAggressiveBackgroundProcessing() {
        audioPlayer?.stop()
        
        keepAliveTimer?.invalidate()
        keepAliveTimer = nil
        
        // End all background tasks in queue
        for taskId in backgroundTaskQueue {
            UIApplication.shared.endBackgroundTask(taskId)
        }
        backgroundTaskQueue.removeAll()
        
        endSecondaryBackgroundTask()
        
        locationManager.stopMonitoringSignificantLocationChanges()
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
        // Live Activity support disabled for now - can be enabled later
        print("Live Activity would start here")
    }
    
    private func updateLiveActivity() {
        // Live Activity support disabled for now - can be enabled later
        print("Live Activity would update here")
    }
    
    private func endLiveActivity() {
        // Live Activity support disabled for now - can be enabled later
        print("Live Activity would end here")
    }
    
    deinit {
        // Clean up without capturing self
        streamingTimer?.invalidate()
        hourlyResetTimer?.invalidate()
        keepAliveTimer?.invalidate()
        
        audioPlayer?.stop()
        locationManager.stopMonitoringSignificantLocationChanges()
        
        Task { @MainActor in
            if backgroundTask != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTask)
            }
            
            if secondaryBackgroundTask != .invalid {
                UIApplication.shared.endBackgroundTask(secondaryBackgroundTask)
            }
            
            // End all queued background tasks
            for taskId in backgroundTaskQueue {
                UIApplication.shared.endBackgroundTask(taskId)
            }
        }
        
        // Live Activity cleanup would go here if enabled
    }
}

// MARK: - Streaming Scenarios

enum StreamingScenario: String, CaseIterable {
    case normal = "Normal patterns"
    case lowStress = "Low stress"
    case stress = "Stress scenario" 
    case extreme = "Extreme events"
    case edgeCases = "Edge cases"
    case workout = "Workout simulation"
    case sleep = "Sleep patterns"
    
    var description: String {
        switch self {
        case .normal:
            return "Realistic daily variations with circadian rhythms"
        case .lowStress:
            return "Relaxed state, higher HRV, lower heart rate"
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
            
        case .lowStress:
            // Lower heart rate for relaxed state
            let relaxDecrease = Double.random(in: 5...15, using: &rng)
            let variation = Double.random(in: -2...2, using: &rng)
            return max(45, min(100, baseline - relaxDecrease + variation))
            
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
            
        case .lowStress:
            // Higher HRV indicates relaxation and low stress
            let relaxIncrease = Double.random(in: 15...30, using: &rng)
            let variation = Double.random(in: -3...5, using: &rng)
            return max(20, min(150, baseline + relaxIncrease + variation))
            
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