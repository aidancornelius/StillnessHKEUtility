//
//  HealthDataModels.swift
//  HealthKitExporter
//
//  Data models for health data export and generation
//

import Foundation
import HealthKit

// MARK: - Exported Data Bundle

struct ExportedHealthBundle: Codable {
    let exportDate: Date
    let startDate: Date
    let endDate: Date
    let heartRate: [HeartRateSample]
    let hrv: [HRVSample]
    let activity: [ActivitySample]
    let sleep: [SleepSample]
    let workouts: [WorkoutSample]
    let restingHeartRate: Double?
    let respiratoryRate: [RespiratorySample]?
    let bloodOxygen: [OxygenSample]?
    let skinTemperature: [TemperatureSample]?
    
    var sampleCount: Int {
        heartRate.count + hrv.count + activity.count + sleep.count + workouts.count +
        (respiratoryRate?.count ?? 0) + (bloodOxygen?.count ?? 0) + (skinTemperature?.count ?? 0)
    }
}

// MARK: - Sample Types (matching Stillness)

struct HeartRateSample: Codable {
    let date: Date
    let value: Double // BPM
    let source: String
}

struct HRVSample: Codable {
    let date: Date
    let value: Double // milliseconds (SDNN)
    let source: String
}

struct ActivitySample: Codable {
    let date: Date
    let endDate: Date
    let stepCount: Double
    let distance: Double? // meters
    let activeCalories: Double?
    let source: String
}

struct SleepSample: Codable {
    let startDate: Date
    let endDate: Date
    let stage: SleepStage
    let source: String
}

enum SleepStage: String, CaseIterable, Codable {
    case awake = "awake"
    case light = "light"
    case deep = "deep"
    case rem = "rem"
    case unknown = "unknown"
}

struct WorkoutSample: Codable {
    let startDate: Date
    let endDate: Date
    let type: String
    let calories: Double?
    let distance: Double? // meters
    let averageHeartRate: Double?
    let source: String
}

struct RespiratorySample: Codable {
    let date: Date
    let value: Double // breaths per minute
}

struct OxygenSample: Codable {
    let date: Date
    let value: Double // percentage
}

struct TemperatureSample: Codable {
    let date: Date
    let value: Double // Celsius
}

// MARK: - Data Type Selection

enum HealthDataType: String, CaseIterable {
    case heartRate = "Heart rate"
    case hrv = "Heart rate variability"
    case activity = "Activity"
    case sleep = "Sleep"
    case workouts = "Workouts"
    case respiratoryRate = "Respiratory rate"
    case bloodOxygen = "Blood oxygen"
    case skinTemperature = "Skin temperature"
    
    var icon: String {
        switch self {
        case .heartRate: return "heart.fill"
        case .hrv: return "waveform.path.ecg"
        case .activity: return "figure.walk"
        case .sleep: return "bed.double.fill"
        case .workouts: return "figure.run"
        case .respiratoryRate: return "lungs.fill"
        case .bloodOxygen: return "drop.fill"
        case .skinTemperature: return "thermometer"
        }
    }
    
    var isEnhanced: Bool {
        switch self {
        case .respiratoryRate, .bloodOxygen, .skinTemperature:
            return true
        default:
            return false
        }
    }
}

// MARK: - Date Transformation

struct DateTransformation: Codable {
    let originalStartDate: Date
    let originalEndDate: Date
    let targetStartDate: Date
    let targetEndDate: Date
    
    func transform(_ date: Date) -> Date {
        let originalInterval = originalEndDate.timeIntervalSince(originalStartDate)
        let targetInterval = targetEndDate.timeIntervalSince(targetStartDate)
        
        let progress = date.timeIntervalSince(originalStartDate) / originalInterval
        let scaledProgress = progress * targetInterval
        
        return targetStartDate.addingTimeInterval(scaledProgress)
    }
}

// MARK: - Pattern Generation

enum PatternType: String, CaseIterable {
    case similar = "Similar pattern"
    case amplified = "Amplified (more stress)"
    case reduced = "Reduced (less stress)"
    case inverted = "Inverted pattern"
    case random = "Random variation"
    
    var description: String {
        switch self {
        case .similar: return "Keep the same stress patterns"
        case .amplified: return "Increase stress levels by 20-40%"
        case .reduced: return "Decrease stress levels by 20-40%"
        case .inverted: return "Flip high and low stress periods"
        case .random: return "Add random variations to the data"
        }
    }
}

struct PatternGenerator {
    static func apply(pattern: PatternType, to samples: [HeartRateSample], seed: Int = 0) -> [HeartRateSample] {
        var rng = SeededRandomGenerator(seed: seed)
        
        switch pattern {
        case .similar:
            return samples.map { sample in
                let variation = Double.random(in: -2...2, using: &rng)
                return HeartRateSample(
                    date: sample.date,
                    value: sample.value + variation,
                    source: sample.source
                )
            }
            
        case .amplified:
            return samples.map { sample in
                let factor = Double.random(in: 1.2...1.4, using: &rng)
                let baselineHR = 70.0
                let amplifiedValue = baselineHR + (sample.value - baselineHR) * factor
                return HeartRateSample(
                    date: sample.date,
                    value: min(200, amplifiedValue),
                    source: sample.source
                )
            }
            
        case .reduced:
            return samples.map { sample in
                let factor = Double.random(in: 0.6...0.8, using: &rng)
                let baselineHR = 70.0
                let reducedValue = baselineHR + (sample.value - baselineHR) * factor
                return HeartRateSample(
                    date: sample.date,
                    value: max(40, reducedValue),
                    source: sample.source
                )
            }
            
        case .inverted:
            let avgHR = samples.map(\.value).reduce(0, +) / Double(samples.count)
            return samples.map { sample in
                let invertedValue = 2 * avgHR - sample.value
                return HeartRateSample(
                    date: sample.date,
                    value: min(200, max(40, invertedValue)),
                    source: sample.source
                )
            }
            
        case .random:
            return samples.map { sample in
                let variation = Double.random(in: -15...15, using: &rng)
                return HeartRateSample(
                    date: sample.date,
                    value: min(200, max(40, sample.value + variation)),
                    source: sample.source
                )
            }
        }
    }
    
    static func apply(pattern: PatternType, to samples: [HRVSample], seed: Int = 0) -> [HRVSample] {
        var rng = SeededRandomGenerator(seed: seed)
        
        switch pattern {
        case .similar:
            return samples.map { sample in
                let variation = Double.random(in: -2...2, using: &rng)
                return HRVSample(
                    date: sample.date,
                    value: max(0, sample.value + variation),
                    source: sample.source
                )
            }
            
        case .amplified:
            return samples.map { sample in
                let factor = Double.random(in: 0.6...0.8, using: &rng) // Lower HRV = more stress
                return HRVSample(
                    date: sample.date,
                    value: max(10, sample.value * factor),
                    source: sample.source
                )
            }
            
        case .reduced:
            return samples.map { sample in
                let factor = Double.random(in: 1.2...1.4, using: &rng) // Higher HRV = less stress
                return HRVSample(
                    date: sample.date,
                    value: min(200, sample.value * factor),
                    source: sample.source
                )
            }
            
        case .inverted:
            let avgHRV = samples.map(\.value).reduce(0, +) / Double(samples.count)
            return samples.map { sample in
                let invertedValue = 2 * avgHRV - sample.value
                return HRVSample(
                    date: sample.date,
                    value: min(200, max(10, invertedValue)),
                    source: sample.source
                )
            }
            
        case .random:
            return samples.map { sample in
                let variation = Double.random(in: -10...10, using: &rng)
                return HRVSample(
                    date: sample.date,
                    value: min(200, max(10, sample.value + variation)),
                    source: sample.source
                )
            }
        }
    }
}

// MARK: - Seeded Random Generator

struct SeededRandomGenerator: RandomNumberGenerator {
    private var state: UInt64
    
    init(seed: Int) {
        self.state = UInt64(seed)
        if state == 0 { state = 1 }
    }
    
    mutating func next() -> UInt64 {
        state = state &* 2862933555777941757 &+ 3037000493
        return state
    }
}