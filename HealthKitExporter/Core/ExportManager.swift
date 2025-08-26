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
        exporter.isSimulator
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
            skinTemperature: transformedSkinTemperature
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