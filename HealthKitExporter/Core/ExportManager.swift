//
//  ExportManager.swift
//  HealthKitExporter
//
//  Manages data export, transformation, and pattern generation
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
class ExportManager: ObservableObject {
    @Published var selectedDataTypes: Set<HealthDataType> = [.heartRate, .hrv, .activity]
    @Published var sourceStartDate = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
    @Published var sourceEndDate = Date()
    @Published var targetStartDate = Date()
    @Published var targetEndDate = Calendar.current.date(byAdding: .day, value: 7, to: Date())!
    @Published var selectedPattern: PatternType = .similar
    @Published var patternSeed = 0
    @Published var lastExportedBundle: ExportedHealthBundle?
    @Published var isGenerating = false
    @Published var generationProgress: Double = 0
    @Published var overrideModeEnabled = false
    @Published var selectedPreset: GenerationPreset = .normal
    @Published var selectedManipulation: DataManipulation = .smoothReplace
    @Published var includeMenstrualData = false
    
    private let exporter = HealthDataExporter()
    
    var isAuthorized: Bool {
        exporter.isAuthorized
    }
    
    var isExporting: Bool {
        exporter.isExporting
    }
    
    var exportProgress: Double {
        exporter.exportProgress
    }
    
    var exportStatus: String {
        exporter.exportStatus
    }
    
    var isSimulator: Bool {
        // Return actual platform unless override is enabled
        overrideModeEnabled ? false : exporter.isSimulator
    }
    
    var actualPlatform: String {
        exporter.isSimulator ? "Simulator" : "Physical Device"
    }
    
    var isImporting: Bool {
        exporter.isImporting
    }
    
    var importProgress: Double {
        exporter.importProgress
    }
    
    var importStatus: String {
        exporter.importStatus
    }
    
    // MARK: - Authorization
    
    func requestAuthorization() async throws {
        try await exporter.requestAuthorization()
    }
    
    // MARK: - Export Original Data
    
    func exportOriginalData() async throws -> ExportedHealthBundle {
        let bundle = try await exporter.exportData(
            from: sourceStartDate,
            to: sourceEndDate,
            dataTypes: selectedDataTypes
        )
        
        lastExportedBundle = bundle
        return bundle
    }
    
    // MARK: - Import Data (Simulator Only)
    
    func importData(_ bundle: ExportedHealthBundle) async throws {
        try await exporter.importData(bundle)
    }
    
    func transposeBundleDatesToToday(_ bundle: ExportedHealthBundle) -> ExportedHealthBundle {
        let originalDuration = bundle.endDate.timeIntervalSince(bundle.startDate)
        let newEndDate = Date()
        let newStartDate = newEndDate.addingTimeInterval(-originalDuration)
        
        // Calculate time offset to apply to all dates
        let timeOffset = newEndDate.timeIntervalSince(bundle.endDate)
        
        // Helper function to transpose a date
        func transposeDate(_ date: Date) -> Date {
            return date.addingTimeInterval(timeOffset)
        }
        
        // Transpose all samples
        let transposedHeartRate = bundle.heartRate.map { sample in
            HeartRateSample(
                date: transposeDate(sample.date),
                value: sample.value,
                source: sample.source
            )
        }
        
        let transposedHRV = bundle.hrv.map { sample in
            HRVSample(
                date: transposeDate(sample.date),
                value: sample.value,
                source: sample.source
            )
        }
        
        let transposedActivity = bundle.activity.map { sample in
            ActivitySample(
                date: transposeDate(sample.date),
                endDate: transposeDate(sample.endDate),
                stepCount: sample.stepCount,
                distance: sample.distance,
                activeCalories: sample.activeCalories,
                source: sample.source
            )
        }
        
        let transposedSleep = bundle.sleep.map { sample in
            SleepSample(
                startDate: transposeDate(sample.startDate),
                endDate: transposeDate(sample.endDate),
                stage: sample.stage,
                source: sample.source
            )
        }
        
        let transposedWorkouts = bundle.workouts.map { workout in
            WorkoutSample(
                startDate: transposeDate(workout.startDate),
                endDate: transposeDate(workout.endDate),
                type: workout.type,
                calories: workout.calories,
                distance: workout.distance,
                averageHeartRate: workout.averageHeartRate,
                source: workout.source
            )
        }
        
        // Transpose optional arrays
        let transposedRespiratory = bundle.respiratoryRate?.map { sample in
            RespiratorySample(
                date: transposeDate(sample.date),
                value: sample.value
            )
        }
        
        let transposedOxygen = bundle.bloodOxygen?.map { sample in
            OxygenSample(
                date: transposeDate(sample.date),
                value: sample.value
            )
        }
        
        let transposedTemperature = bundle.skinTemperature?.map { sample in
            TemperatureSample(
                date: transposeDate(sample.date),
                value: sample.value
            )
        }
        
        let transposedWheelchair = bundle.wheelchairActivity?.map { sample in
            WheelchairActivitySample(
                date: transposeDate(sample.date),
                endDate: transposeDate(sample.endDate),
                pushCount: sample.pushCount,
                distance: sample.distance,
                source: sample.source
            )
        }
        
        let transposedExercise = bundle.exerciseTime?.map { sample in
            ExerciseTimeSample(
                date: transposeDate(sample.date),
                endDate: transposeDate(sample.endDate),
                minutes: sample.minutes,
                source: sample.source
            )
        }
        
        let transposedBodyTemp = bundle.bodyTemperature?.map { sample in
            BodyTemperatureSample(
                date: transposeDate(sample.date),
                value: sample.value,
                source: sample.source
            )
        }
        
        let transposedMenstrual = bundle.menstrualFlow?.map { sample in
            MenstrualFlowSample(
                date: transposeDate(sample.date),
                endDate: transposeDate(sample.endDate),
                flowLevel: sample.flowLevel,
                isCycleStart: sample.isCycleStart,
                source: sample.source
            )
        }
        
        return ExportedHealthBundle(
            exportDate: Date(),
            startDate: newStartDate,
            endDate: newEndDate,
            heartRate: transposedHeartRate,
            hrv: transposedHRV,
            activity: transposedActivity,
            sleep: transposedSleep,
            workouts: transposedWorkouts,
            restingHeartRate: bundle.restingHeartRate,
            respiratoryRate: transposedRespiratory,
            bloodOxygen: transposedOxygen,
            skinTemperature: transposedTemperature,
            wheelchairActivity: transposedWheelchair,
            exerciseTime: transposedExercise,
            bodyTemperature: transposedBodyTemp,
            menstrualFlow: transposedMenstrual
        )
    }
    
    // MARK: - Generate Synthetic Data
    
    func generateSyntheticData() async -> ExportedHealthBundle {
        isGenerating = true
        generationProgress = 0
        
        defer {
            isGenerating = false
            generationProgress = 1.0
        }
        
        return SyntheticDataGenerator.generateHealthData(
            preset: selectedPreset,
            manipulation: selectedManipulation,
            startDate: targetStartDate,
            endDate: targetEndDate,
            existingBundle: lastExportedBundle,
            seed: patternSeed,
            includeMenstrualData: includeMenstrualData
        )
    }
    
    // MARK: - Generate Transformed Data
    
    func generateTransformedData(from bundle: ExportedHealthBundle) async -> ExportedHealthBundle {
        isGenerating = true
        generationProgress = 0
        
        defer {
            isGenerating = false
            generationProgress = 1.0
        }
        
        let transformation = DateTransformation(
            originalStartDate: bundle.startDate,
            originalEndDate: bundle.endDate,
            targetStartDate: targetStartDate,
            targetEndDate: targetEndDate
        )
        
        // Transform dates and apply patterns
        generationProgress = 0.1
        
        let transformedHeartRate = bundle.heartRate.map { sample in
            HeartRateSample(
                date: transformation.transform(sample.date),
                value: sample.value,
                source: "Generated from \(sample.source)"
            )
        }
        
        generationProgress = 0.2
        
        let transformedHRV = bundle.hrv.map { sample in
            HRVSample(
                date: transformation.transform(sample.date),
                value: sample.value,
                source: "Generated from \(sample.source)"
            )
        }
        
        generationProgress = 0.3
        
        // Apply pattern modifications
        let patternedHeartRate = PatternGenerator.apply(
            pattern: selectedPattern,
            to: transformedHeartRate,
            seed: patternSeed
        )
        
        generationProgress = 0.5
        
        let patternedHRV = PatternGenerator.apply(
            pattern: selectedPattern,
            to: transformedHRV,
            seed: patternSeed
        )
        
        generationProgress = 0.7
        
        // Transform other data types
        let transformedActivity = bundle.activity.map { sample in
            ActivitySample(
                date: transformation.transform(sample.date),
                endDate: transformation.transform(sample.endDate),
                stepCount: sample.stepCount,
                distance: sample.distance,
                activeCalories: sample.activeCalories,
                source: "Generated from \(sample.source)"
            )
        }
        
        let transformedSleep = bundle.sleep.map { sample in
            SleepSample(
                startDate: transformation.transform(sample.startDate),
                endDate: transformation.transform(sample.endDate),
                stage: sample.stage,
                source: "Generated from \(sample.source)"
            )
        }
        
        let transformedWorkouts = bundle.workouts.map { sample in
            WorkoutSample(
                startDate: transformation.transform(sample.startDate),
                endDate: transformation.transform(sample.endDate),
                type: sample.type,
                calories: sample.calories,
                distance: sample.distance,
                averageHeartRate: sample.averageHeartRate,
                source: "Generated from \(sample.source)"
            )
        }
        
        generationProgress = 0.9
        
        // Transform enhanced metrics if available
        let transformedRespiratoryRate = bundle.respiratoryRate?.map { sample in
            RespiratorySample(
                date: transformation.transform(sample.date),
                value: applyPatternToValue(sample.value, baseValue: 15, pattern: selectedPattern)
            )
        }
        
        let transformedBloodOxygen = bundle.bloodOxygen?.map { sample in
            OxygenSample(
                date: transformation.transform(sample.date),
                value: applyPatternToValue(sample.value, baseValue: 97, pattern: selectedPattern, inverted: true)
            )
        }
        
        let transformedSkinTemperature = bundle.skinTemperature?.map { sample in
            TemperatureSample(
                date: transformation.transform(sample.date),
                value: applyPatternToValue(sample.value, baseValue: 36.5, pattern: selectedPattern)
            )
        }
        
        // Transform new data types
        let transformedWheelchairActivity = bundle.wheelchairActivity?.map { sample in
            WheelchairActivitySample(
                date: transformation.transform(sample.date),
                endDate: transformation.transform(sample.endDate),
                pushCount: applyPatternToValue(sample.pushCount, baseValue: 100, pattern: selectedPattern),
                distance: sample.distance.map { applyPatternToValue($0, baseValue: 500, pattern: selectedPattern) },
                source: sample.source
            )
        }
        
        let transformedExerciseTime = bundle.exerciseTime?.map { sample in
            ExerciseTimeSample(
                date: transformation.transform(sample.date),
                endDate: transformation.transform(sample.endDate),
                minutes: applyPatternToValue(sample.minutes, baseValue: 30, pattern: selectedPattern),
                source: sample.source
            )
        }
        
        let transformedBodyTemperature = bundle.bodyTemperature?.map { sample in
            BodyTemperatureSample(
                date: transformation.transform(sample.date),
                value: applyPatternToValue(sample.value, baseValue: 37.0, pattern: selectedPattern),
                source: sample.source
            )
        }
        
        let transformedMenstrualFlow = bundle.menstrualFlow?.map { sample in
            MenstrualFlowSample(
                date: transformation.transform(sample.date),
                endDate: transformation.transform(sample.endDate),
                flowLevel: sample.flowLevel, // Keep flow level as-is
                isCycleStart: sample.isCycleStart,
                source: sample.source
            )
        }
        
        return ExportedHealthBundle(
            exportDate: Date(),
            startDate: targetStartDate,
            endDate: targetEndDate,
            heartRate: patternedHeartRate,
            hrv: patternedHRV,
            activity: transformedActivity,
            sleep: transformedSleep,
            workouts: transformedWorkouts,
            restingHeartRate: bundle.restingHeartRate,
            respiratoryRate: transformedRespiratoryRate,
            bloodOxygen: transformedBloodOxygen,
            skinTemperature: transformedSkinTemperature,
            wheelchairActivity: transformedWheelchairActivity,
            exerciseTime: transformedExerciseTime,
            bodyTemperature: transformedBodyTemperature,
            menstrualFlow: transformedMenstrualFlow
        )
    }
    
    // MARK: - File Operations
    
    func saveToFile(_ bundle: ExportedHealthBundle) throws -> URL {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        let data = try encoder.encode(bundle)
        
        let fileName = "health_export_\(ISO8601DateFormatter().string(from: bundle.exportDate)).json"
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsPath.appendingPathComponent(fileName)
        
        try data.write(to: fileURL)
        return fileURL
    }
    
    func loadFromFile(_ url: URL) throws -> ExportedHealthBundle {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ExportedHealthBundle.self, from: data)
    }
    
    // MARK: - Helper Methods
    
    private func applyPatternToValue(_ value: Double, baseValue: Double, pattern: PatternType, inverted: Bool = false) -> Double {
        switch pattern {
        case .similar:
            return value + Double.random(in: -0.5...0.5)
        case .amplified:
            let factor = inverted ? 0.8 : 1.2
            return baseValue + (value - baseValue) * factor
        case .reduced:
            let factor = inverted ? 1.2 : 0.8
            return baseValue + (value - baseValue) * factor
        case .inverted:
            return 2 * baseValue - value
        case .random:
            return value + Double.random(in: -2...2)
        }
    }
}

// MARK: - Document for SwiftUI

struct HealthDataDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    
    var bundle: ExportedHealthBundle
    
    init(bundle: ExportedHealthBundle) {
        self.bundle = bundle
    }
    
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        bundle = try decoder.decode(ExportedHealthBundle.self, from: data)
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        let data = try encoder.encode(bundle)
        return FileWrapper(regularFileWithContents: data)
    }
}