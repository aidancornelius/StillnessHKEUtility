//
//  HealthKitExporterApp.swift
//  HealthKitExporter
//
//  Health data export and test data generation app
//

import SwiftUI

@main
struct HealthKitExporterApp: App {
    @StateObject private var exportManager = ExportManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(exportManager)
        }
    }
}