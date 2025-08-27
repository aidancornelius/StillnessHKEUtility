//
//  HealthKitExporterApp.swift
//  HealthKitExporter
//
//  Health data export and test data generation app
//

import SwiftUI
import BackgroundTasks

@main
struct HealthKitExporterApp: App {
    @StateObject private var exportManager = ExportManager()
    @StateObject private var liveStreamManager = LiveStreamManager()
    
    init() {
        // Register background task identifier
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.healthkitexporter.datastreaming", using: nil) { task in
            Self.handleBackgroundDataStreaming(task: task as! BGAppRefreshTask)
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(exportManager)
                .environmentObject(liveStreamManager)
        }
    }
    
    private static func handleBackgroundDataStreaming(task: BGAppRefreshTask) {
        // Schedule next background refresh
        scheduleNextBackgroundAppRefresh()
        
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }
        
        // Always complete the task for now - the LiveStreamManager handles its own background processing
        task.setTaskCompleted(success: true)
    }
    
    private static func scheduleNextBackgroundAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: "com.healthkitexporter.datastreaming")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30)
        
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("Failed to schedule next background refresh: \(error)")
        }
    }
}