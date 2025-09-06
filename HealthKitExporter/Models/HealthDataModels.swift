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
    let wheelchairActivity: [WheelchairActivitySample]?
    let exerciseTime: [ExerciseTimeSample]?
    let bodyTemperature: [BodyTemperatureSample]?
    let menstrualFlow: [MenstrualFlowSample]?
    
    var sampleCount: Int {
        var count = 0
        count += heartRate.count
        count += hrv.count
        count += activity.count
        count += sleep.count
        count += workouts.count
        count += respiratoryRate?.count ?? 0
        count += bloodOxygen?.count ?? 0
        count += skinTemperature?.count ?? 0
        count += wheelchairActivity?.count ?? 0
        count += exerciseTime?.count ?? 0
        count += bodyTemperature?.count ?? 0
        count += menstrualFlow?.count ?? 0
        return count
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

struct WheelchairActivitySample: Codable {
    let date: Date
    let endDate: Date
    let pushCount: Double
    let distance: Double? // meters
    let source: String
}

struct ExerciseTimeSample: Codable {
    let date: Date
    let endDate: Date
    let minutes: Double
    let source: String
}

struct BodyTemperatureSample: Codable {
    let date: Date
    let value: Double // Celsius
    let source: String
}

struct MenstrualFlowSample: Codable {
    let date: Date
    let endDate: Date
    let flowLevel: MenstrualFlowLevel
    let isCycleStart: Bool
    let source: String
}

enum MenstrualFlowLevel: String, CaseIterable, Codable {
    case unspecified = "unspecified"
    case light = "light"
    case medium = "medium"
    case heavy = "heavy"
    case none = "none"
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
    case wheelchairActivity = "Wheelchair activity"
    case exerciseTime = "Exercise time"
    case bodyTemperature = "Body temperature"
    case menstrualFlow = "Menstrual flow"
    
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
        case .wheelchairActivity: return "figure.roll"
        case .exerciseTime: return "timer"
        case .bodyTemperature: return "thermometer.medium"
        case .menstrualFlow: return "drop.circle"
        }
    }
    
    var isEnhanced: Bool {
        switch self {
        case .respiratoryRate, .bloodOxygen, .skinTemperature, .bodyTemperature, .menstrualFlow:
            return true
        default:
            return false
        }
    }
    
    var isAccessibilityFeature: Bool {
        switch self {
        case .wheelchairActivity:
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

// MARK: - Generation Presets

enum GenerationPreset: String, CaseIterable {
    case lowerStress = "Lower stress"
    case normal = "Normal results"
    case higherStress = "Higher stress"
    case edgeCases = "Edge cases"
    
    var description: String {
        switch self {
        case .lowerStress: return "Healthy, relaxed patterns"
        case .normal: return "Typical daily patterns"
        case .higherStress: return "Elevated stress indicators"
        case .edgeCases: return "Extreme values for testing"
        }
    }
    
    var heartRateRange: ClosedRange<Double> {
        switch self {
        case .lowerStress: return 55...75
        case .normal: return 60...85
        case .higherStress: return 75...110
        case .edgeCases: return 40...180
        }
    }
    
    var hrvRange: ClosedRange<Double> {
        switch self {
        case .lowerStress: return 50...100  // Higher HRV = less stress
        case .normal: return 30...70
        case .higherStress: return 15...40  // Lower HRV = more stress
        case .edgeCases: return 5...150
        }
    }
    
    var stepsRange: ClosedRange<Double> {
        switch self {
        case .lowerStress: return 8000...12000
        case .normal: return 5000...10000
        case .higherStress: return 2000...5000
        case .edgeCases: return 0...30000
        }
    }
    
    var sleepHours: ClosedRange<Double> {
        switch self {
        case .lowerStress: return 7.5...9.0
        case .normal: return 6.5...8.0
        case .higherStress: return 4.0...6.5
        case .edgeCases: return 2.0...12.0
        }
    }
}

// MARK: - Data Manipulation Options

enum DataManipulation: String, CaseIterable {
    case keepOriginal = "Keep original"
    case generateMissing = "Generate missing data"
    case smoothReplace = "Smooth & replace"
    case accessibilityMode = "Accessibility mode"
    
    var description: String {
        switch self {
        case .keepOriginal: return "Preserve existing data patterns"
        case .generateMissing: return "Add data for empty categories"
        case .smoothReplace: return "Replace with synthetic data"
        case .accessibilityMode: return "Replace steps with wheelchair data"
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

// MARK: - Synthetic Data Generator

struct SyntheticDataGenerator {
    static func generateHealthData(
        preset: GenerationPreset,
        manipulation: DataManipulation,
        startDate: Date,
        endDate: Date,
        existingBundle: ExportedHealthBundle? = nil,
        seed: Int = 0,
        includeMenstrualData: Bool = false
    ) -> ExportedHealthBundle {
        var rng = SeededRandomGenerator(seed: seed)
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: startDate, to: endDate).day ?? 7
        
        // Generate or modify data based on manipulation type
        switch manipulation {
        case .keepOriginal:
            return existingBundle ?? generateCompleteBundle(preset: preset, startDate: startDate, endDate: endDate, includeMenstrualData: includeMenstrualData, rng: &rng)
            
        case .generateMissing:
            return fillMissingData(in: existingBundle, preset: preset, startDate: startDate, endDate: endDate, includeMenstrualData: includeMenstrualData, rng: &rng)
            
        case .smoothReplace:
            return generateCompleteBundle(preset: preset, startDate: startDate, endDate: endDate, includeMenstrualData: includeMenstrualData, rng: &rng)
            
        case .accessibilityMode:
            return generateAccessibilityBundle(preset: preset, startDate: startDate, endDate: endDate, existingBundle: existingBundle, includeMenstrualData: includeMenstrualData, rng: &rng)
        }
    }
    
    private static func generateCompleteBundle(
        preset: GenerationPreset,
        startDate: Date,
        endDate: Date,
        includeMenstrualData: Bool,
        rng: inout SeededRandomGenerator
    ) -> ExportedHealthBundle {
        let heartRate = generateHeartRateData(preset: preset, startDate: startDate, endDate: endDate, rng: &rng)
        let hrv = generateHRVData(preset: preset, startDate: startDate, endDate: endDate, rng: &rng)
        let activity = generateActivityData(preset: preset, startDate: startDate, endDate: endDate, rng: &rng)
        let sleep = generateSleepData(preset: preset, startDate: startDate, endDate: endDate, rng: &rng)
        let workouts = generateWorkoutData(preset: preset, startDate: startDate, endDate: endDate, rng: &rng)
        
        return ExportedHealthBundle(
            exportDate: Date(),
            startDate: startDate,
            endDate: endDate,
            heartRate: heartRate,
            hrv: hrv,
            activity: activity,
            sleep: sleep,
            workouts: workouts,
            restingHeartRate: Double.random(in: 50...70, using: &rng),
            respiratoryRate: generateRespiratoryData(preset: preset, startDate: startDate, endDate: endDate, rng: &rng),
            bloodOxygen: generateOxygenData(preset: preset, startDate: startDate, endDate: endDate, rng: &rng),
            skinTemperature: generateTemperatureData(preset: preset, startDate: startDate, endDate: endDate, rng: &rng),
            wheelchairActivity: nil,
            exerciseTime: generateExerciseTimeData(preset: preset, startDate: startDate, endDate: endDate, rng: &rng),
            bodyTemperature: generateBodyTemperatureData(preset: preset, startDate: startDate, endDate: endDate, rng: &rng),
            menstrualFlow: includeMenstrualData ? generateMenstrualData(startDate: startDate, endDate: endDate, rng: &rng) : nil
        )
    }
    
    private static func fillMissingData(
        in bundle: ExportedHealthBundle?,
        preset: GenerationPreset,
        startDate: Date,
        endDate: Date,
        includeMenstrualData: Bool,
        rng: inout SeededRandomGenerator
    ) -> ExportedHealthBundle {
        guard let bundle = bundle else {
            return generateCompleteBundle(preset: preset, startDate: startDate, endDate: endDate, includeMenstrualData: includeMenstrualData, rng: &rng)
        }
        
        return ExportedHealthBundle(
            exportDate: Date(),
            startDate: startDate,
            endDate: endDate,
            heartRate: bundle.heartRate.isEmpty ? generateHeartRateData(preset: preset, startDate: startDate, endDate: endDate, rng: &rng) : bundle.heartRate,
            hrv: bundle.hrv.isEmpty ? generateHRVData(preset: preset, startDate: startDate, endDate: endDate, rng: &rng) : bundle.hrv,
            activity: bundle.activity.isEmpty ? generateActivityData(preset: preset, startDate: startDate, endDate: endDate, rng: &rng) : bundle.activity,
            sleep: bundle.sleep.isEmpty ? generateSleepData(preset: preset, startDate: startDate, endDate: endDate, rng: &rng) : bundle.sleep,
            workouts: bundle.workouts.isEmpty ? generateWorkoutData(preset: preset, startDate: startDate, endDate: endDate, rng: &rng) : bundle.workouts,
            restingHeartRate: bundle.restingHeartRate ?? Double.random(in: 50...70, using: &rng),
            respiratoryRate: bundle.respiratoryRate ?? generateRespiratoryData(preset: preset, startDate: startDate, endDate: endDate, rng: &rng),
            bloodOxygen: bundle.bloodOxygen ?? generateOxygenData(preset: preset, startDate: startDate, endDate: endDate, rng: &rng),
            skinTemperature: bundle.skinTemperature ?? generateTemperatureData(preset: preset, startDate: startDate, endDate: endDate, rng: &rng),
            wheelchairActivity: bundle.wheelchairActivity ?? (Bool.random(using: &rng) ? generateWheelchairData(preset: preset, startDate: startDate, endDate: endDate, rng: &rng) : nil),
            exerciseTime: bundle.exerciseTime ?? generateExerciseTimeData(preset: preset, startDate: startDate, endDate: endDate, rng: &rng),
            bodyTemperature: bundle.bodyTemperature ?? generateBodyTemperatureData(preset: preset, startDate: startDate, endDate: endDate, rng: &rng),
            menstrualFlow: bundle.menstrualFlow ?? (includeMenstrualData ? generateMenstrualData(startDate: startDate, endDate: endDate, rng: &rng) : nil)
        )
    }
    
    private static func generateAccessibilityBundle(
        preset: GenerationPreset,
        startDate: Date,
        endDate: Date,
        existingBundle: ExportedHealthBundle?,
        includeMenstrualData: Bool,
        rng: inout SeededRandomGenerator
    ) -> ExportedHealthBundle {
        // Convert steps to wheelchair pushes
        let wheelchairData = generateWheelchairData(preset: preset, startDate: startDate, endDate: endDate, rng: &rng)
        
        if let bundle = existingBundle {
            return ExportedHealthBundle(
                exportDate: Date(),
                startDate: startDate,
                endDate: endDate,
                heartRate: bundle.heartRate,
                hrv: bundle.hrv,
                activity: [], // Remove steps
                sleep: bundle.sleep,
                workouts: bundle.workouts,
                restingHeartRate: bundle.restingHeartRate,
                respiratoryRate: bundle.respiratoryRate,
                bloodOxygen: bundle.bloodOxygen,
                skinTemperature: bundle.skinTemperature,
                wheelchairActivity: wheelchairData, // Add wheelchair data
                exerciseTime: bundle.exerciseTime,
                bodyTemperature: bundle.bodyTemperature,
                menstrualFlow: includeMenstrualData ? bundle.menstrualFlow : nil
            )
        } else {
            var bundle = generateCompleteBundle(preset: preset, startDate: startDate, endDate: endDate, includeMenstrualData: includeMenstrualData, rng: &rng)
            return ExportedHealthBundle(
                exportDate: bundle.exportDate,
                startDate: bundle.startDate,
                endDate: bundle.endDate,
                heartRate: bundle.heartRate,
                hrv: bundle.hrv,
                activity: [], // Remove steps
                sleep: bundle.sleep,
                workouts: bundle.workouts,
                restingHeartRate: bundle.restingHeartRate,
                respiratoryRate: bundle.respiratoryRate,
                bloodOxygen: bundle.bloodOxygen,
                skinTemperature: bundle.skinTemperature,
                wheelchairActivity: wheelchairData, // Add wheelchair data
                exerciseTime: bundle.exerciseTime,
                bodyTemperature: bundle.bodyTemperature,
                menstrualFlow: includeMenstrualData ? bundle.menstrualFlow : nil
            )
        }
    }
    
    // Individual data generators
    private static func generateHeartRateData(preset: GenerationPreset, startDate: Date, endDate: Date, rng: inout SeededRandomGenerator) -> [HeartRateSample] {
        var samples: [HeartRateSample] = []
        var currentDate = startDate
        
        while currentDate < endDate {
            let value = Double.random(in: preset.heartRateRange, using: &rng)
            samples.append(HeartRateSample(date: currentDate, value: value, source: "HealthKitExporter"))
            currentDate = currentDate.addingTimeInterval(300) // Every 5 minutes
        }
        return samples
    }
    
    private static func generateHRVData(preset: GenerationPreset, startDate: Date, endDate: Date, rng: inout SeededRandomGenerator) -> [HRVSample] {
        var samples: [HRVSample] = []
        var currentDate = startDate
        
        while currentDate < endDate {
            let value = Double.random(in: preset.hrvRange, using: &rng)
            samples.append(HRVSample(date: currentDate, value: value, source: "HealthKitExporter"))
            currentDate = currentDate.addingTimeInterval(3600) // Every hour
        }
        return samples
    }
    
    private static func generateActivityData(preset: GenerationPreset, startDate: Date, endDate: Date, rng: inout SeededRandomGenerator) -> [ActivitySample] {
        var samples: [ActivitySample] = []
        var currentDate = startDate
        let calendar = Calendar.current
        
        while currentDate < endDate {
            let endHour = currentDate.addingTimeInterval(3600)
            let steps = Double.random(in: preset.stepsRange, using: &rng) / 24 // Hourly steps
            let distance = steps * 0.75 // Average step length in meters
            let calories = steps * 0.05 // Rough calorie estimate
            
            samples.append(ActivitySample(
                date: currentDate,
                endDate: endHour,
                stepCount: steps,
                distance: distance,
                activeCalories: calories,
                source: "HealthKitExporter"
            ))
            currentDate = endHour
        }
        return samples
    }
    
    private static func generateSleepData(preset: GenerationPreset, startDate: Date, endDate: Date, rng: inout SeededRandomGenerator) -> [SleepSample] {
        var samples: [SleepSample] = []
        var currentDate = startDate
        let calendar = Calendar.current
        
        while currentDate < endDate {
            // Sleep from 10 PM to 6 AM (adjust based on preset)
            let sleepStart = calendar.date(bySettingHour: 22, minute: 0, second: 0, of: currentDate)!
            let sleepHours = Double.random(in: preset.sleepHours, using: &rng)
            let sleepEnd = sleepStart.addingTimeInterval(sleepHours * 3600)
            
            // Generate sleep stages
            var sleepTime = sleepStart
            while sleepTime < sleepEnd {
                let stageDuration = Double.random(in: 20...90, using: &rng) * 60 // 20-90 minute stages
                let stageEnd = min(sleepTime.addingTimeInterval(stageDuration), sleepEnd)
                
                let stages: [SleepStage] = [.light, .deep, .rem]
                let stage = stages.randomElement(using: &rng)!
                
                samples.append(SleepSample(
                    startDate: sleepTime,
                    endDate: stageEnd,
                    stage: stage,
                    source: "HealthKitExporter"
                ))
                
                sleepTime = stageEnd
            }
            
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }
        return samples
    }
    
    private static func generateWorkoutData(preset: GenerationPreset, startDate: Date, endDate: Date, rng: inout SeededRandomGenerator) -> [WorkoutSample] {
        var samples: [WorkoutSample] = []
        var currentDate = startDate
        let calendar = Calendar.current
        
        while currentDate < endDate {
            // One workout per day
            let workoutStart = calendar.date(bySettingHour: Int.random(in: 6...20, using: &rng), minute: 0, second: 0, of: currentDate)!
            let duration = Double.random(in: 20...60, using: &rng) * 60 // 20-60 minutes
            let workoutEnd = workoutStart.addingTimeInterval(duration)
            
            let types = ["Running", "Walking", "Cycling", "Yoga", "Strength training"]
            let type = types.randomElement(using: &rng)!
            
            samples.append(WorkoutSample(
                startDate: workoutStart,
                endDate: workoutEnd,
                type: type,
                calories: Double.random(in: 100...500, using: &rng),
                distance: type == "Running" || type == "Cycling" ? Double.random(in: 1000...10000, using: &rng) : nil,
                averageHeartRate: Double.random(in: preset.heartRateRange, using: &rng),
                source: "HealthKitExporter"
            ))
            
            currentDate = calendar.date(byAdding: .day, value: Int.random(in: 1...3, using: &rng), to: currentDate)!
        }
        return samples
    }
    
    private static func generateWheelchairData(preset: GenerationPreset, startDate: Date, endDate: Date, rng: inout SeededRandomGenerator) -> [WheelchairActivitySample] {
        var samples: [WheelchairActivitySample] = []
        var currentDate = startDate
        
        while currentDate < endDate {
            let endHour = currentDate.addingTimeInterval(3600)
            let pushes = Double.random(in: 50...200, using: &rng) // Hourly pushes
            let distance = pushes * 2.5 // Average push distance in meters
            
            samples.append(WheelchairActivitySample(
                date: currentDate,
                endDate: endHour,
                pushCount: pushes,
                distance: distance,
                source: "HealthKitExporter"
            ))
            currentDate = endHour
        }
        return samples
    }
    
    private static func generateExerciseTimeData(preset: GenerationPreset, startDate: Date, endDate: Date, rng: inout SeededRandomGenerator) -> [ExerciseTimeSample] {
        var samples: [ExerciseTimeSample] = []
        var currentDate = startDate
        
        while currentDate < endDate {
            let minutes = Double.random(in: 0...60, using: &rng)
            if minutes > 5 { // Only record if more than 5 minutes
                samples.append(ExerciseTimeSample(
                    date: currentDate,
                    endDate: currentDate.addingTimeInterval(minutes * 60),
                    minutes: minutes,
                    source: "HealthKitExporter"
                ))
            }
            currentDate = currentDate.addingTimeInterval(86400) // Daily
        }
        return samples
    }
    
    private static func generateRespiratoryData(preset: GenerationPreset, startDate: Date, endDate: Date, rng: inout SeededRandomGenerator) -> [RespiratorySample] {
        var samples: [RespiratorySample] = []
        var currentDate = startDate
        
        while currentDate < endDate {
            let rate = preset == .higherStress ? Double.random(in: 16...20, using: &rng) : Double.random(in: 12...16, using: &rng)
            samples.append(RespiratorySample(date: currentDate, value: rate))
            currentDate = currentDate.addingTimeInterval(3600) // Hourly
        }
        return samples
    }
    
    private static func generateOxygenData(preset: GenerationPreset, startDate: Date, endDate: Date, rng: inout SeededRandomGenerator) -> [OxygenSample] {
        var samples: [OxygenSample] = []
        var currentDate = startDate
        
        while currentDate < endDate {
            let oxygen = preset == .edgeCases ? Double.random(in: 85...100, using: &rng) : Double.random(in: 95...100, using: &rng)
            samples.append(OxygenSample(date: currentDate, value: oxygen))
            currentDate = currentDate.addingTimeInterval(3600) // Hourly
        }
        return samples
    }
    
    private static func generateTemperatureData(preset: GenerationPreset, startDate: Date, endDate: Date, rng: inout SeededRandomGenerator) -> [TemperatureSample] {
        var samples: [TemperatureSample] = []
        var currentDate = startDate
        
        while currentDate < endDate {
            let temp = Double.random(in: 36.0...37.5, using: &rng)
            samples.append(TemperatureSample(date: currentDate, value: temp))
            currentDate = currentDate.addingTimeInterval(3600) // Hourly
        }
        return samples
    }
    
    private static func generateBodyTemperatureData(preset: GenerationPreset, startDate: Date, endDate: Date, rng: inout SeededRandomGenerator) -> [BodyTemperatureSample] {
        var samples: [BodyTemperatureSample] = []
        var currentDate = startDate
        
        while currentDate < endDate {
            let temp = preset == .higherStress ? Double.random(in: 37.2...38.0, using: &rng) : Double.random(in: 36.5...37.2, using: &rng)
            samples.append(BodyTemperatureSample(date: currentDate, value: temp, source: "HealthKitExporter"))
            currentDate = currentDate.addingTimeInterval(43200) // Twice daily
        }
        return samples
    }
    
    private static func generateMenstrualData(startDate: Date, endDate: Date, rng: inout SeededRandomGenerator) -> [MenstrualFlowSample] {
        var samples: [MenstrualFlowSample] = []
        var currentDate = startDate
        let calendar = Calendar.current
        
        // Generate monthly cycles
        while currentDate < endDate {
            // Period lasts 3-7 days
            let periodDays = Int.random(in: 3...7, using: &rng)
            
            for day in 0..<periodDays {
                let dayStart = calendar.date(byAdding: .day, value: day, to: currentDate)!
                let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
                
                let flowLevel: MenstrualFlowLevel
                if day == 0 || day == periodDays - 1 {
                    flowLevel = .light
                } else if day == 1 || day == 2 {
                    flowLevel = Bool.random(using: &rng) ? .medium : .heavy
                } else {
                    flowLevel = .medium
                }
                
                samples.append(MenstrualFlowSample(
                    date: dayStart,
                    endDate: dayEnd,
                    flowLevel: flowLevel,
                    isCycleStart: day == 0, // First day of period is cycle start
                    source: "HealthKitExporter"
                ))
            }
            
            // Next cycle in 28-35 days
            currentDate = calendar.date(byAdding: .day, value: Int.random(in: 28...35, using: &rng), to: currentDate)!
        }
        return samples
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