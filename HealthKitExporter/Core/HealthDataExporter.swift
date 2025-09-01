//
//  HealthDataExporter.swift
//  HealthKitExporter
//
//  Core HealthKit data fetching and export functionality
//  Also supports importing data when running in simulator
//

import Foundation
import HealthKit

@MainActor
class HealthDataExporter: ObservableObject {
    private let healthStore = HKHealthStore()
    
    @Published var isAuthorized = false
    @Published var isExporting = false
    @Published var exportProgress: Double = 0
    @Published var exportStatus = ""
    @Published var isImporting = false
    @Published var importProgress: Double = 0
    @Published var importStatus = ""
    
    // MARK: - Platform Detection
    
    var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }
    
    // MARK: - Authorization
    
    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw ExportError.healthKitUnavailable
        }
        
        var typesToRead: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
            HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
            HKObjectType.workoutType(),
            // New types for Equilibria compatibility
            HKObjectType.quantityType(forIdentifier: .pushCount)!,
            HKObjectType.quantityType(forIdentifier: .distanceWheelchair)!,
            HKObjectType.quantityType(forIdentifier: .appleExerciseTime)!,
            HKObjectType.quantityType(forIdentifier: .bodyTemperature)!,
            HKObjectType.categoryType(forIdentifier: .menstrualFlow)!
        ]
        
        // Add enhanced metrics if available
        if #available(iOS 16.0, *) {
            if let respiratoryType = HKQuantityType.quantityType(forIdentifier: .respiratoryRate) {
                typesToRead.insert(respiratoryType)
            }
            if let oxygenType = HKQuantityType.quantityType(forIdentifier: .oxygenSaturation) {
                typesToRead.insert(oxygenType)
            }
        }
        
        if #available(iOS 17.0, *) {
            if let tempType = HKQuantityType.quantityType(forIdentifier: .appleSleepingWristTemperature) {
                typesToRead.insert(tempType)
            }
        }
        
        // If in simulator, also request write permissions for importing
        var typesToWrite: Set<HKSampleType> = []
        if isSimulator {
            typesToWrite = [
                HKObjectType.quantityType(forIdentifier: .heartRate)!,
                // Note: restingHeartRate is typically read-only (calculated by Apple)
                HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
                HKObjectType.quantityType(forIdentifier: .stepCount)!,
                HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
                HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
                HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
                HKObjectType.workoutType(),
                // New types for Equilibria compatibility
                HKObjectType.quantityType(forIdentifier: .pushCount)!,
                HKObjectType.quantityType(forIdentifier: .distanceWheelchair)!,
                // Note: appleExerciseTime is read-only, cannot write to it
                HKObjectType.quantityType(forIdentifier: .bodyTemperature)!,
                HKObjectType.categoryType(forIdentifier: .menstrualFlow)!
            ]
            
            // Note: respiratoryRate and oxygenSaturation might be read-only depending on iOS version
            // Note: appleExerciseTime is read-only (calculated by Apple)
            // Note: appleSleepingWristTemperature is read-only, cannot write to it
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            healthStore.requestAuthorization(toShare: typesToWrite.isEmpty ? nil : typesToWrite, read: typesToRead) { [weak self] success, error in
                Task { @MainActor in
                    self?.isAuthorized = success
                }
                
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
    
    // MARK: - Data Export
    
    func exportData(
        from startDate: Date,
        to endDate: Date,
        dataTypes: Set<HealthDataType>
    ) async throws -> ExportedHealthBundle {
        isExporting = true
        exportProgress = 0
        exportStatus = "Starting export..."
        
        defer {
            isExporting = false
            exportProgress = 1.0
            exportStatus = "Export complete"
        }
        
        var heartRate: [HeartRateSample] = []
        var hrv: [HRVSample] = []
        var activity: [ActivitySample] = []
        var sleep: [SleepSample] = []
        var workouts: [WorkoutSample] = []
        var restingHeartRate: Double? = nil
        var respiratoryRate: [RespiratorySample]? = nil
        var bloodOxygen: [OxygenSample]? = nil
        var skinTemperature: [TemperatureSample]? = nil
        var wheelchairActivity: [WheelchairActivitySample]? = nil
        var exerciseTime: [ExerciseTimeSample]? = nil
        var bodyTemperature: [BodyTemperatureSample]? = nil
        var menstrualFlow: [MenstrualFlowSample]? = nil
        
        let totalSteps = dataTypes.count
        var currentStep = 0
        
        // Fetch each requested data type
        if dataTypes.contains(.heartRate) {
            exportStatus = "Fetching heart rate data..."
            heartRate = try await fetchHeartRate(from: startDate, to: endDate)
            restingHeartRate = try await fetchRestingHeartRate()
            currentStep += 1
            exportProgress = Double(currentStep) / Double(totalSteps)
        }
        
        if dataTypes.contains(.hrv) {
            exportStatus = "Fetching HRV data..."
            hrv = try await fetchHRV(from: startDate, to: endDate)
            currentStep += 1
            exportProgress = Double(currentStep) / Double(totalSteps)
        }
        
        if dataTypes.contains(.activity) {
            exportStatus = "Fetching activity data..."
            activity = try await fetchActivity(from: startDate, to: endDate)
            currentStep += 1
            exportProgress = Double(currentStep) / Double(totalSteps)
        }
        
        if dataTypes.contains(.sleep) {
            exportStatus = "Fetching sleep data..."
            sleep = try await fetchSleep(from: startDate, to: endDate)
            currentStep += 1
            exportProgress = Double(currentStep) / Double(totalSteps)
        }
        
        if dataTypes.contains(.workouts) {
            exportStatus = "Fetching workout data..."
            workouts = try await fetchWorkouts(from: startDate, to: endDate)
            currentStep += 1
            exportProgress = Double(currentStep) / Double(totalSteps)
        }
        
        if dataTypes.contains(.respiratoryRate) {
            exportStatus = "Fetching respiratory rate..."
            respiratoryRate = try await fetchRespiratoryRate(from: startDate, to: endDate)
            currentStep += 1
            exportProgress = Double(currentStep) / Double(totalSteps)
        }
        
        if dataTypes.contains(.bloodOxygen) {
            exportStatus = "Fetching blood oxygen..."
            bloodOxygen = try await fetchBloodOxygen(from: startDate, to: endDate)
            currentStep += 1
            exportProgress = Double(currentStep) / Double(totalSteps)
        }
        
        if dataTypes.contains(.skinTemperature) {
            exportStatus = "Fetching skin temperature..."
            skinTemperature = try await fetchSkinTemperature(from: startDate, to: endDate)
            currentStep += 1
            exportProgress = Double(currentStep) / Double(totalSteps)
        }
        
        if dataTypes.contains(.wheelchairActivity) {
            exportStatus = "Fetching wheelchair activity..."
            wheelchairActivity = try await fetchWheelchairActivity(from: startDate, to: endDate)
            currentStep += 1
            exportProgress = Double(currentStep) / Double(totalSteps)
        }
        
        if dataTypes.contains(.exerciseTime) {
            exportStatus = "Fetching exercise time..."
            exerciseTime = try await fetchExerciseTime(from: startDate, to: endDate)
            currentStep += 1
            exportProgress = Double(currentStep) / Double(totalSteps)
        }
        
        if dataTypes.contains(.bodyTemperature) {
            exportStatus = "Fetching body temperature..."
            bodyTemperature = try await fetchBodyTemperature(from: startDate, to: endDate)
            currentStep += 1
            exportProgress = Double(currentStep) / Double(totalSteps)
        }
        
        if dataTypes.contains(.menstrualFlow) {
            exportStatus = "Fetching menstrual flow data..."
            menstrualFlow = try await fetchMenstrualFlow(from: startDate, to: endDate)
            currentStep += 1
            exportProgress = Double(currentStep) / Double(totalSteps)
        }
        
        return ExportedHealthBundle(
            exportDate: Date(),
            startDate: startDate,
            endDate: endDate,
            heartRate: heartRate,
            hrv: hrv,
            activity: activity,
            sleep: sleep,
            workouts: workouts,
            restingHeartRate: restingHeartRate,
            respiratoryRate: respiratoryRate,
            bloodOxygen: bloodOxygen,
            skinTemperature: skinTemperature,
            wheelchairActivity: wheelchairActivity,
            exerciseTime: exerciseTime,
            bodyTemperature: bodyTemperature,
            menstrualFlow: menstrualFlow
        )
    }
    
    // MARK: - Individual Data Fetchers
    
    private func fetchHeartRate(from startDate: Date, to endDate: Date) async throws -> [HeartRateSample] {
        let type = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let unit = HKUnit.count().unitDivided(by: .minute())
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        
        return try await withCheckedThrowingContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(sampleType: type, predicate: predicate,
                                     limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    let heartRateSamples = (samples as? [HKQuantitySample] ?? []).map { sample in
                        HeartRateSample(
                            date: sample.startDate,
                            value: sample.quantity.doubleValue(for: unit),
                            source: sample.sourceRevision.source.name
                        )
                    }
                    continuation.resume(returning: heartRateSamples)
                }
            }
            healthStore.execute(query)
        }
    }
    
    private func fetchRestingHeartRate() async throws -> Double? {
        let type = HKQuantityType.quantityType(forIdentifier: .restingHeartRate)!
        let unit = HKUnit.count().unitDivided(by: .minute())
        let predicate = HKQuery.predicateForSamples(withStart: Date.distantPast, end: Date(), options: .strictStartDate)
        
        return try await withCheckedThrowingContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(sampleType: type, predicate: predicate,
                                     limit: 1, sortDescriptors: [sort]) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let sample = samples?.first as? HKQuantitySample {
                    continuation.resume(returning: sample.quantity.doubleValue(for: unit))
                } else {
                    continuation.resume(returning: nil)
                }
            }
            healthStore.execute(query)
        }
    }
    
    private func fetchHRV(from startDate: Date, to endDate: Date) async throws -> [HRVSample] {
        let type = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!
        let unit = HKUnit.secondUnit(with: .milli)
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        
        return try await withCheckedThrowingContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(sampleType: type, predicate: predicate,
                                     limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    let hrvSamples = (samples as? [HKQuantitySample] ?? []).map { sample in
                        HRVSample(
                            date: sample.startDate,
                            value: sample.quantity.doubleValue(for: unit),
                            source: sample.sourceRevision.source.name
                        )
                    }
                    continuation.resume(returning: hrvSamples)
                }
            }
            healthStore.execute(query)
        }
    }
    
    private func fetchActivity(from startDate: Date, to endDate: Date) async throws -> [ActivitySample] {
        let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        // let distanceType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!
        // let caloriesType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
        
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        
        // Fetch steps
        let steps = try await fetchQuantitySamples(type: stepType, unit: HKUnit.count(), predicate: predicate)
        
        // Create activity samples from steps (simplified - in real app would correlate all data)
        return steps.map { step in
            ActivitySample(
                date: step.startDate,
                endDate: step.endDate,
                stepCount: step.value,
                distance: nil,
                activeCalories: nil,
                source: step.source
            )
        }
    }
    
    private func fetchSleep(from startDate: Date, to endDate: Date) async throws -> [SleepSample] {
        let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        
        return try await withCheckedThrowingContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate,
                                     limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    let sleepSamples = (samples as? [HKCategorySample] ?? []).compactMap { sample -> SleepSample? in
                        guard let value = HKCategoryValueSleepAnalysis(rawValue: sample.value) else { return nil }
                        
                        let stage: SleepStage
                        switch value {
                        case .awake: stage = .awake
                        case .asleepCore: stage = .light
                        case .asleepDeep: stage = .deep
                        case .asleepREM: stage = .rem
                        default: stage = .unknown
                        }
                        
                        return SleepSample(
                            startDate: sample.startDate,
                            endDate: sample.endDate,
                            stage: stage,
                            source: sample.sourceRevision.source.name
                        )
                    }
                    continuation.resume(returning: sleepSamples)
                }
            }
            healthStore.execute(query)
        }
    }
    
    private func fetchWorkouts(from startDate: Date, to endDate: Date) async throws -> [WorkoutSample] {
        let type = HKObjectType.workoutType()
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        
        return try await withCheckedThrowingContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(sampleType: type, predicate: predicate,
                                     limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    let workoutSamples = (samples as? [HKWorkout] ?? []).map { workout in
                        WorkoutSample(
                            startDate: workout.startDate,
                            endDate: workout.endDate,
                            type: workout.workoutActivityType.name,
                            calories: nil, // workout.totalEnergyBurned deprecated in iOS 18
                            distance: workout.totalDistance?.doubleValue(for: .meter()),
                            averageHeartRate: nil,
                            source: workout.sourceRevision.source.name
                        )
                    }
                    continuation.resume(returning: workoutSamples)
                }
            }
            healthStore.execute(query)
        }
    }
    
    private func fetchRespiratoryRate(from startDate: Date, to endDate: Date) async throws -> [RespiratorySample]? {
        guard #available(iOS 16.0, *),
              let type = HKQuantityType.quantityType(forIdentifier: .respiratoryRate) else {
            return nil
        }
        
        let unit = HKUnit.count().unitDivided(by: .minute())
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        
        let samples = try await fetchQuantitySamples(type: type, unit: unit, predicate: predicate)
        return samples.map { RespiratorySample(date: $0.startDate, value: $0.value) }
    }
    
    private func fetchBloodOxygen(from startDate: Date, to endDate: Date) async throws -> [OxygenSample]? {
        guard #available(iOS 16.0, *),
              let type = HKQuantityType.quantityType(forIdentifier: .oxygenSaturation) else {
            return nil
        }
        
        let unit = HKUnit.percent()
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        
        let samples = try await fetchQuantitySamples(type: type, unit: unit, predicate: predicate)
        return samples.map { OxygenSample(date: $0.startDate, value: $0.value * 100) }
    }
    
    private func fetchSkinTemperature(from startDate: Date, to endDate: Date) async throws -> [TemperatureSample]? {
        guard #available(iOS 17.0, *),
              let type = HKQuantityType.quantityType(forIdentifier: .appleSleepingWristTemperature) else {
            return nil
        }
        
        let unit = HKUnit.degreeCelsius()
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        
        let samples = try await fetchQuantitySamples(type: type, unit: unit, predicate: predicate)
        return samples.map { TemperatureSample(date: $0.startDate, value: $0.value) }
    }
    
    private func fetchWheelchairActivity(from startDate: Date, to endDate: Date) async throws -> [WheelchairActivitySample]? {
        let pushType = HKQuantityType.quantityType(forIdentifier: .pushCount)!
        let distanceType = HKQuantityType.quantityType(forIdentifier: .distanceWheelchair)!
        
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        
        // Fetch pushes
        let pushes = try await fetchQuantitySamples(type: pushType, unit: HKUnit.count(), predicate: predicate)
        
        // Fetch distance
        let distances = try await fetchQuantitySamples(type: distanceType, unit: HKUnit.meter(), predicate: predicate)
        
        // Combine data (simplified - in real app would correlate by time)
        return pushes.map { push in
            WheelchairActivitySample(
                date: push.startDate,
                endDate: push.endDate,
                pushCount: push.value,
                distance: distances.first(where: { abs($0.startDate.timeIntervalSince(push.startDate)) < 60 })?.value,
                source: push.source
            )
        }
    }
    
    private func fetchExerciseTime(from startDate: Date, to endDate: Date) async throws -> [ExerciseTimeSample]? {
        let type = HKQuantityType.quantityType(forIdentifier: .appleExerciseTime)!
        let unit = HKUnit.minute()
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        
        let samples = try await fetchQuantitySamples(type: type, unit: unit, predicate: predicate)
        return samples.map { ExerciseTimeSample(date: $0.startDate, endDate: $0.endDate, minutes: $0.value, source: $0.source) }
    }
    
    private func fetchBodyTemperature(from startDate: Date, to endDate: Date) async throws -> [BodyTemperatureSample]? {
        let type = HKQuantityType.quantityType(forIdentifier: .bodyTemperature)!
        let unit = HKUnit.degreeCelsius()
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        
        let samples = try await fetchQuantitySamples(type: type, unit: unit, predicate: predicate)
        return samples.map { BodyTemperatureSample(date: $0.startDate, value: $0.value, source: $0.source) }
    }
    
    private func fetchMenstrualFlow(from startDate: Date, to endDate: Date) async throws -> [MenstrualFlowSample]? {
        let type = HKObjectType.categoryType(forIdentifier: .menstrualFlow)!
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        
        return try await withCheckedThrowingContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(sampleType: type, predicate: predicate,
                                     limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    let flowSamples = (samples as? [HKCategorySample] ?? []).compactMap { sample -> MenstrualFlowSample? in
                        guard let value = HKCategoryValueMenstrualFlow(rawValue: sample.value) else { return nil }
                        
                        let flowLevel: MenstrualFlowLevel
                        switch value {
                        case .unspecified: flowLevel = .unspecified
                        case .light: flowLevel = .light
                        case .medium: flowLevel = .medium
                        case .heavy: flowLevel = .heavy
                        case .none: flowLevel = .none
                        @unknown default: flowLevel = .unspecified
                        }
                        
                        return MenstrualFlowSample(
                            date: sample.startDate,
                            endDate: sample.endDate,
                            flowLevel: flowLevel,
                            source: sample.sourceRevision.source.name
                        )
                    }
                    continuation.resume(returning: flowSamples)
                }
            }
            healthStore.execute(query)
        }
    }
    
    // MARK: - Data Import (Simulator Only)
    
    func importData(_ bundle: ExportedHealthBundle) async throws {
        guard isSimulator else {
            throw ExportError.exportFailed("Import is only available in simulator")
        }
        
        isImporting = true
        importProgress = 0
        importStatus = "Starting import..."
        
        defer {
            isImporting = false
            importProgress = 1.0
            importStatus = "Import complete"
        }
        
        let totalSamples = bundle.sampleCount
        var processedSamples = 0
        
        // Import heart rate data
        if !bundle.heartRate.isEmpty {
            importStatus = "Importing heart rate data..."
            try await importHeartRateSamples(bundle.heartRate)
            processedSamples += bundle.heartRate.count
            importProgress = Double(processedSamples) / Double(totalSamples)
        }
        
        // Import HRV data
        if !bundle.hrv.isEmpty {
            importStatus = "Importing HRV data..."
            try await importHRVSamples(bundle.hrv)
            processedSamples += bundle.hrv.count
            importProgress = Double(processedSamples) / Double(totalSamples)
        }
        
        // Import activity data
        if !bundle.activity.isEmpty {
            importStatus = "Importing activity data..."
            try await importActivitySamples(bundle.activity)
            processedSamples += bundle.activity.count
            importProgress = Double(processedSamples) / Double(totalSamples)
        }
        
        // Import sleep data
        if !bundle.sleep.isEmpty {
            importStatus = "Importing sleep data..."
            try await importSleepSamples(bundle.sleep)
            processedSamples += bundle.sleep.count
            importProgress = Double(processedSamples) / Double(totalSamples)
        }
        
        // Import workout data
        if !bundle.workouts.isEmpty {
            importStatus = "Importing workout data..."
            try await importWorkoutSamples(bundle.workouts)
            processedSamples += bundle.workouts.count
            importProgress = Double(processedSamples) / Double(totalSamples)
        }
        
        // Import enhanced metrics
        if let respiratory = bundle.respiratoryRate, !respiratory.isEmpty {
            importStatus = "Importing respiratory rate..."
            try await importRespiratorySamples(respiratory)
            processedSamples += respiratory.count
            importProgress = Double(processedSamples) / Double(totalSamples)
        }
        
        if let oxygen = bundle.bloodOxygen, !oxygen.isEmpty {
            importStatus = "Importing blood oxygen..."
            try await importOxygenSamples(oxygen)
            processedSamples += oxygen.count
            importProgress = Double(processedSamples) / Double(totalSamples)
        }
        
        // Note: Skin temperature is read-only in HealthKit, cannot import it
        if let temp = bundle.skinTemperature, !temp.isEmpty {
            importStatus = "Skipping skin temperature (read-only)..."
            processedSamples += temp.count
            importProgress = Double(processedSamples) / Double(totalSamples)
        }
        
        // Import wheelchair activity
        if let wheelchair = bundle.wheelchairActivity, !wheelchair.isEmpty {
            importStatus = "Importing wheelchair activity..."
            try await importWheelchairSamples(wheelchair)
            processedSamples += wheelchair.count
            importProgress = Double(processedSamples) / Double(totalSamples)
        }
        
        // Import exercise time (Note: appleExerciseTime is read-only, skip import)
        if let exercise = bundle.exerciseTime, !exercise.isEmpty {
            importStatus = "Skipping exercise time (read-only)..."
            // Cannot import appleExerciseTime as it's calculated by Apple
            processedSamples += exercise.count
            importProgress = Double(processedSamples) / Double(totalSamples)
        }
        
        // Import body temperature
        if let bodyTemp = bundle.bodyTemperature, !bodyTemp.isEmpty {
            importStatus = "Importing body temperature..."
            try await importBodyTemperatureSamples(bodyTemp)
            processedSamples += bodyTemp.count
            importProgress = Double(processedSamples) / Double(totalSamples)
        }
        
        // Import menstrual flow
        if let menstrual = bundle.menstrualFlow, !menstrual.isEmpty {
            importStatus = "Importing menstrual flow data..."
            try await importMenstrualFlowSamples(menstrual)
            processedSamples += menstrual.count
            importProgress = Double(processedSamples) / Double(totalSamples)
        }
    }
    
    private func importHeartRateSamples(_ samples: [HeartRateSample]) async throws {
        let type = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let unit = HKUnit.count().unitDivided(by: .minute())
        
        let hkSamples = samples.map { sample in
            let quantity = HKQuantity(unit: unit, doubleValue: sample.value)
            return HKQuantitySample(
                type: type,
                quantity: quantity,
                start: sample.date,
                end: sample.date
            )
        }
        
        try await saveSamples(hkSamples)
    }
    
    private func importHRVSamples(_ samples: [HRVSample]) async throws {
        let type = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!
        let unit = HKUnit.secondUnit(with: .milli)
        
        let hkSamples = samples.map { sample in
            let quantity = HKQuantity(unit: unit, doubleValue: sample.value)
            return HKQuantitySample(
                type: type,
                quantity: quantity,
                start: sample.date,
                end: sample.date
            )
        }
        
        try await saveSamples(hkSamples)
    }
    
    private func importActivitySamples(_ samples: [ActivitySample]) async throws {
        let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        let stepUnit = HKUnit.count()
        
        let stepSamples = samples.map { sample in
            let quantity = HKQuantity(unit: stepUnit, doubleValue: sample.stepCount)
            return HKQuantitySample(
                type: stepType,
                quantity: quantity,
                start: sample.date,
                end: sample.endDate
            )
        }
        
        try await saveSamples(stepSamples)
        
        // Import distance if available
        let distanceType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!
        let distanceUnit = HKUnit.meter()
        
        let distanceSamples = samples.compactMap { sample -> HKQuantitySample? in
            guard let distance = sample.distance else { return nil }
            let quantity = HKQuantity(unit: distanceUnit, doubleValue: distance)
            return HKQuantitySample(
                type: distanceType,
                quantity: quantity,
                start: sample.date,
                end: sample.endDate
            )
        }
        
        if !distanceSamples.isEmpty {
            try await saveSamples(distanceSamples)
        }
    }
    
    private func importSleepSamples(_ samples: [SleepSample]) async throws {
        let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)!
        
        let hkSamples = samples.compactMap { sample -> HKCategorySample? in
            let value: HKCategoryValueSleepAnalysis
            switch sample.stage {
            case .awake: value = .awake
            case .light: value = .asleepCore
            case .deep: value = .asleepDeep
            case .rem: value = .asleepREM
            case .unknown: value = .asleepUnspecified
            }
            
            return HKCategorySample(
                type: type,
                value: value.rawValue,
                start: sample.startDate,
                end: sample.endDate
            )
        }
        
        try await saveSamples(hkSamples)
    }
    
    private func importWorkoutSamples(_ samples: [WorkoutSample]) async throws {
        for sample in samples {
            let workoutType = workoutActivityType(from: sample.type)
            
            let workout = HKWorkout(
                activityType: workoutType,
                start: sample.startDate,
                end: sample.endDate,
                duration: sample.endDate.timeIntervalSince(sample.startDate),
                totalEnergyBurned: sample.calories.map { HKQuantity(unit: .kilocalorie(), doubleValue: $0) },
                totalDistance: sample.distance.map { HKQuantity(unit: .meter(), doubleValue: $0) },
                metadata: nil
            )
            
            try await saveSample(workout)
        }
    }
    
    private func importRespiratorySamples(_ samples: [RespiratorySample]) async throws {
        // Respiratory rate might be read-only, skip if not available
        guard #available(iOS 16.0, *),
              let type = HKQuantityType.quantityType(forIdentifier: .respiratoryRate) else {
            return
        }
        
        // Try to import but don't fail if it's read-only
        do {
            let unit = HKUnit.count().unitDivided(by: .minute())
            
            let hkSamples = samples.map { sample in
                let quantity = HKQuantity(unit: unit, doubleValue: sample.value)
                return HKQuantitySample(
                    type: type,
                    quantity: quantity,
                    start: sample.date,
                    end: sample.date
                )
            }
            
            try await saveSamples(hkSamples)
        } catch {
            // Silently skip if we can't write this type
            print("Could not import respiratory rate: \(error)")
        }
    }
    
    private func importOxygenSamples(_ samples: [OxygenSample]) async throws {
        // Blood oxygen might be read-only, skip if not available
        guard #available(iOS 16.0, *),
              let type = HKQuantityType.quantityType(forIdentifier: .oxygenSaturation) else {
            return
        }
        
        // Try to import but don't fail if it's read-only
        do {
            let unit = HKUnit.percent()
            
            let hkSamples = samples.map { sample in
                let quantity = HKQuantity(unit: unit, doubleValue: sample.value / 100.0)
                return HKQuantitySample(
                    type: type,
                    quantity: quantity,
                    start: sample.date,
                    end: sample.date
                )
            }
            
            try await saveSamples(hkSamples)
        } catch {
            // Silently skip if we can't write this type
            print("Could not import blood oxygen: \(error)")
        }
    }
    
    private func importTemperatureSamples(_ samples: [TemperatureSample]) async throws {
        // Skin temperature is read-only in HealthKit, cannot be imported
        // This function is kept for compatibility but does nothing
        return
    }
    
    private func importWheelchairSamples(_ samples: [WheelchairActivitySample]) async throws {
        let pushType = HKQuantityType.quantityType(forIdentifier: .pushCount)!
        let pushUnit = HKUnit.count()
        
        let pushSamples = samples.map { sample in
            let quantity = HKQuantity(unit: pushUnit, doubleValue: sample.pushCount)
            return HKQuantitySample(
                type: pushType,
                quantity: quantity,
                start: sample.date,
                end: sample.endDate
            )
        }
        
        try await saveSamples(pushSamples)
        
        // Import distance if available
        let distanceType = HKQuantityType.quantityType(forIdentifier: .distanceWheelchair)!
        let distanceUnit = HKUnit.meter()
        
        let distanceSamples = samples.compactMap { sample -> HKQuantitySample? in
            guard let distance = sample.distance else { return nil }
            let quantity = HKQuantity(unit: distanceUnit, doubleValue: distance)
            return HKQuantitySample(
                type: distanceType,
                quantity: quantity,
                start: sample.date,
                end: sample.endDate
            )
        }
        
        if !distanceSamples.isEmpty {
            try await saveSamples(distanceSamples)
        }
    }
    
    private func importExerciseTimeSamples(_ samples: [ExerciseTimeSample]) async throws {
        // appleExerciseTime is read-only in HealthKit - it's calculated automatically by Apple
        // based on movement and heart rate data. We cannot write to it directly.
        // This method is kept for compatibility but does nothing.
        return
    }
    
    private func importBodyTemperatureSamples(_ samples: [BodyTemperatureSample]) async throws {
        let type = HKQuantityType.quantityType(forIdentifier: .bodyTemperature)!
        let unit = HKUnit.degreeCelsius()
        
        let hkSamples = samples.map { sample in
            let quantity = HKQuantity(unit: unit, doubleValue: sample.value)
            return HKQuantitySample(
                type: type,
                quantity: quantity,
                start: sample.date,
                end: sample.date
            )
        }
        
        try await saveSamples(hkSamples)
    }
    
    private func importMenstrualFlowSamples(_ samples: [MenstrualFlowSample]) async throws {
        let type = HKCategoryType.categoryType(forIdentifier: .menstrualFlow)!
        
        let hkSamples = samples.compactMap { sample -> HKCategorySample? in
            let value: HKCategoryValueMenstrualFlow
            switch sample.flowLevel {
            case .unspecified: value = .unspecified
            case .light: value = .light
            case .medium: value = .medium
            case .heavy: value = .heavy
            case .none: value = .none
            }
            
            return HKCategorySample(
                type: type,
                value: value.rawValue,
                start: sample.date,
                end: sample.endDate
            )
        }
        
        try await saveSamples(hkSamples)
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
    
    private func saveSamples(_ samples: [HKSample]) async throws {
        guard !samples.isEmpty else { return }
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.save(samples) { success, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
    
    private func workoutActivityType(from name: String) -> HKWorkoutActivityType {
        switch name.lowercased() {
        case "running": return .running
        case "walking": return .walking
        case "cycling": return .cycling
        case "swimming": return .swimming
        case "yoga": return .yoga
        case "strength training", "weight training": return .functionalStrengthTraining
        case "hiit": return .highIntensityIntervalTraining
        case "hiking": return .hiking
        case "elliptical": return .elliptical
        case "rowing": return .rowing
        case "dance": return .socialDance // .dance deprecated in iOS 14
        case "pilates": return .pilates
        case "boxing": return .boxing
        default: return .other
        }
    }
    
    // MARK: - Helper Methods
    
    private func fetchQuantitySamples(
        type: HKQuantityType,
        unit: HKUnit,
        predicate: NSPredicate
    ) async throws -> [(startDate: Date, endDate: Date, value: Double, source: String)] {
        return try await withCheckedThrowingContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(sampleType: type, predicate: predicate,
                                     limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    let quantitySamples = (samples as? [HKQuantitySample] ?? []).map { sample in
                        (startDate: sample.startDate, 
                         endDate: sample.endDate,
                         value: sample.quantity.doubleValue(for: unit),
                         source: sample.sourceRevision.source.name)
                    }
                    continuation.resume(returning: quantitySamples)
                }
            }
            healthStore.execute(query)
        }
    }
}

// MARK: - Error Types

enum ExportError: LocalizedError {
    case healthKitUnavailable
    case authorizationDenied
    case exportFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .healthKitUnavailable:
            return "HealthKit is not available on this device"
        case .authorizationDenied:
            return "HealthKit access was denied"
        case .exportFailed(let reason):
            return "Export failed: \(reason)"
        }
    }
}

// MARK: - Extensions

private extension HKWorkoutActivityType {
    var name: String {
        switch self {
        case .running: return "Running"
        case .walking: return "Walking"
        case .cycling: return "Cycling"
        case .swimming: return "Swimming"
        case .yoga: return "Yoga"
        case .functionalStrengthTraining: return "Strength training"
        case .traditionalStrengthTraining: return "Weight training"
        case .crossTraining: return "Cross training"
        case .mixedCardio: return "Mixed cardio"
        case .highIntensityIntervalTraining: return "HIIT"
        case .hiking: return "Hiking"
        case .elliptical: return "Elliptical"
        case .rowing: return "Rowing"
        case .stairClimbing: return "Stair climbing"
        case .dance: return "Dance"
        case .pilates: return "Pilates"
        case .boxing: return "Boxing"
        case .kickboxing: return "Kickboxing"
        case .martialArts: return "Martial arts"
        default: return "Workout"
        }
    }
}