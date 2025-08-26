//
//  ContentView.swift
//  HealthKitExporter
//
//  Main app interface with tab navigation
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var exportManager: ExportManager
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            if exportManager.isSimulator {
                // Show import view in simulator
                ImportView()
                    .tabItem {
                        Label("Import data", systemImage: "square.and.arrow.down")
                    }
                    .tag(0)
            } else {
                // Show export view on device
                ExportView()
                    .tabItem {
                        Label("Export data", systemImage: "square.and.arrow.up")
                    }
                    .tag(0)
            }
            
            GeneratorView()
                .tabItem {
                    Label("Generate patterns", systemImage: "waveform.path")
                }
                .tag(1)
            
            if exportManager.isSimulator {
                LiveStreamView()
                    .tabItem {
                        Label("Live stream", systemImage: "dot.radiowaves.left.and.right")
                    }
                    .tag(2)
            }
            
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(exportManager.isSimulator ? 3 : 2)
        }
        .task {
            if !exportManager.isAuthorized {
                try? await exportManager.requestAuthorization()
            }
        }
    }
}

// MARK: - Import View (Simulator Only)

struct ImportView: View {
    @EnvironmentObject var exportManager: ExportManager
    @State private var showingFilePicker = false
    @State private var loadedBundle: ExportedHealthBundle?
    @State private var errorMessage: String?
    @State private var importSuccessful = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Import health data") {
                    Text("Running in simulator")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text("Import JSON files to populate the simulator's HealthKit database with test data.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Section("Select data file") {
                    if let bundle = loadedBundle {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("\(bundle.sampleCount) samples", systemImage: "doc.text.fill")
                            
                            HStack {
                                Text("Date range:")
                                    .foregroundStyle(.secondary)
                                Text("\(bundle.startDate, style: .date) - \(bundle.endDate, style: .date)")
                                    .font(.caption)
                            }
                        }
                        
                        Button(action: { showingFilePicker = true }) {
                            Label("Load different file", systemImage: "doc.badge.arrow.up")
                        }
                    } else {
                        Button(action: { showingFilePicker = true }) {
                            Label("Load JSON file", systemImage: "doc.badge.arrow.up")
                        }
                    }
                }
                
                if let bundle = loadedBundle {
                    Section("Data preview") {
                        if !bundle.heartRate.isEmpty {
                            LabeledContent("Heart rate", value: "\(bundle.heartRate.count) samples")
                        }
                        if !bundle.hrv.isEmpty {
                            LabeledContent("HRV", value: "\(bundle.hrv.count) samples")
                        }
                        if !bundle.activity.isEmpty {
                            LabeledContent("Activity", value: "\(bundle.activity.count) samples")
                        }
                        if !bundle.sleep.isEmpty {
                            LabeledContent("Sleep", value: "\(bundle.sleep.count) samples")
                        }
                        if !bundle.workouts.isEmpty {
                            LabeledContent("Workouts", value: "\(bundle.workouts.count)")
                        }
                    }
                    
                    Section("Import to HealthKit") {
                        if exportManager.isImporting {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(exportManager.importStatus)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                
                                ProgressView(value: exportManager.importProgress)
                                    .progressViewStyle(.linear)
                            }
                        } else {
                            Button(action: importData) {
                                Label("Import to simulator", systemImage: "square.and.arrow.down.on.square")
                            }
                            .disabled(loadedBundle == nil)
                            
                            if importSuccessful {
                                Label("Import successful", systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                }
                
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Import to simulator")
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        loadFile(url)
                    }
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func loadFile(_ url: URL) {
        do {
            _ = url.startAccessingSecurityScopedResource()
            defer { url.stopAccessingSecurityScopedResource() }
            
            loadedBundle = try exportManager.loadFromFile(url)
            errorMessage = nil
            importSuccessful = false
        } catch {
            errorMessage = "Failed to load file: \(error.localizedDescription)"
        }
    }
    
    private func importData() {
        guard let bundle = loadedBundle else { return }
        
        importSuccessful = false
        Task {
            do {
                try await exportManager.importData(bundle)
                importSuccessful = true
                errorMessage = nil
            } catch {
                errorMessage = "Import failed: \(error.localizedDescription)"
                importSuccessful = false
            }
        }
    }
}

// MARK: - Generator View

struct GeneratorView: View {
    @EnvironmentObject var exportManager: ExportManager
    @State private var showingFilePicker = false
    @State private var showingExporter = false
    @State private var generatedBundle: ExportedHealthBundle?
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Source data") {
                    if let bundle = exportManager.lastExportedBundle {
                        HStack {
                            Label("\(bundle.sampleCount) samples", systemImage: "chart.line.uptrend.xyaxis")
                            Spacer()
                            Text(bundle.exportDate, style: .date)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Button(action: { showingFilePicker = true }) {
                            Label("Load exported data", systemImage: "doc.badge.arrow.up")
                        }
                    }
                }
                
                Section("Target date range") {
                    DatePicker("Start date", selection: $exportManager.targetStartDate, displayedComponents: [.date, .hourAndMinute])
                    DatePicker("End date", selection: $exportManager.targetEndDate, displayedComponents: [.date, .hourAndMinute])
                }
                
                Section("Pattern generation") {
                    Picker("Pattern type", selection: $exportManager.selectedPattern) {
                        ForEach(PatternType.allCases, id: \.self) { pattern in
                            VStack(alignment: .leading) {
                                Text(pattern.rawValue)
                                Text(pattern.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .tag(pattern)
                        }
                    }
                    .pickerStyle(.menu)
                    
                    Stepper("Random seed: \(exportManager.patternSeed)", value: $exportManager.patternSeed, in: 0...100)
                }
                
                Section {
                    Button(action: generateData) {
                        if exportManager.isGenerating {
                            HStack {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .scaleEffect(0.8)
                                Text("Generating...")
                            }
                        } else {
                            Label("Generate test data", systemImage: "sparkles")
                        }
                    }
                    .disabled(exportManager.lastExportedBundle == nil || exportManager.isGenerating)
                    
                    if let generated = generatedBundle {
                        Button(action: { showingExporter = true }) {
                            Label("Export \(generated.sampleCount) samples", systemImage: "square.and.arrow.down")
                        }
                    }
                }
                
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Pattern generator")
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        loadFile(url)
                    }
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
            .fileExporter(
                isPresented: $showingExporter,
                document: generatedBundle.map { HealthDataDocument(bundle: $0) },
                contentType: .json,
                defaultFilename: "generated_health_data.json"
            ) { result in
                switch result {
                case .success:
                    errorMessage = nil
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func loadFile(_ url: URL) {
        do {
            _ = url.startAccessingSecurityScopedResource()
            defer { url.stopAccessingSecurityScopedResource() }
            
            exportManager.lastExportedBundle = try exportManager.loadFromFile(url)
            errorMessage = nil
        } catch {
            errorMessage = "Failed to load file: \(error.localizedDescription)"
        }
    }
    
    private func generateData() {
        guard let sourceBundle = exportManager.lastExportedBundle else { return }
        
        Task {
            generatedBundle = await exportManager.generateTransformedData(from: sourceBundle)
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @EnvironmentObject var exportManager: ExportManager
    @AppStorage("defaultDaysToExport") private var defaultDaysToExport = 7
    @AppStorage("includeEnhancedMetrics") private var includeEnhancedMetrics = true
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Export defaults") {
                    Stepper("Days to export: \(defaultDaysToExport)", value: $defaultDaysToExport, in: 1...365)
                    Toggle("Include enhanced metrics", isOn: $includeEnhancedMetrics)
                }
                
                Section("About") {
                    LabeledContent("Version", value: "1.0.0")
                    LabeledContent("Purpose", value: "Development testing")
                    
                    Link(destination: URL(string: "https://github.com/aidancornelius/StillnessHKEUtility")!) {
                        Label("View source", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                }
                
                Section {
                    Button("Request HealthKit permissions") {
                        Task {
                            try? await exportManager.requestAuthorization()
                        }
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(ExportManager())
}
