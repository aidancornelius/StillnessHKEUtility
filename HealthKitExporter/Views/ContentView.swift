//
//  ContentView.swift
//  HealthKitExporter
//
//  Main app interface with tab navigation
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var exportManager: ExportManager
    @EnvironmentObject var liveStreamManager: LiveStreamManager
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            if exportManager.overrideModeEnabled {
                // Show both export and import when override is enabled
                ExportView()
                    .tabItem {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .tag(0)
                
                ImportView()
                    .tabItem {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                    .tag(1)
            } else if exportManager.isSimulator {
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
                    Label("Generate", systemImage: "waveform.path")
                }
                .tag(exportManager.overrideModeEnabled ? 2 : 1)
            
            if exportManager.isSimulator || exportManager.overrideModeEnabled {
                LiveStreamView()
                    .tabItem {
                        Label("Live generate", systemImage: "dot.radiowaves.left.and.right")
                    }
                    .tag(exportManager.overrideModeEnabled ? 3 : 2)
            }
            
            NetworkStreamView(liveStreamManager: liveStreamManager)
                .tabItem {
                    Label("Network stream", systemImage: "wifi.router")
                }
                .tag(exportManager.overrideModeEnabled ? 4 : (exportManager.isSimulator ? 3 : 2))
            
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: exportManager.overrideModeEnabled ? "exclamationmark.gear" : "gear")
                }
                .tag(exportManager.overrideModeEnabled ? 5 : (exportManager.isSimulator ? 4 : 3))
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
    @State private var transposeDatesToToday = true
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Import health data") {
                    if exportManager.overrideModeEnabled {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text("Override mode active - Running on \(exportManager.actualPlatform)")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        .padding(.vertical, 4)
                    } else {
                        Text("Running in simulator")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
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
                    
                    Section("Date adjustment") {
                        Toggle("Transpose dates to end today", isOn: $transposeDatesToToday)
                        
                        if transposeDatesToToday {
                            let duration = bundle.endDate.timeIntervalSince(bundle.startDate)
                            let newStartDate = Date().addingTimeInterval(-duration)
                            let newEndDate = Date()
                            
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "calendar.badge.clock")
                                        .foregroundStyle(.blue)
                                    Text("Dates will be shifted")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("Original:")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text("\(bundle.startDate, style: .date) → \(bundle.endDate, style: .date)")
                                            .font(.caption)
                                    }
                                    
                                    HStack {
                                        Text("New:")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text("\(newStartDate, style: .date) → \(newEndDate, style: .date)")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                    }
                                }
                                
                                Text("All data timestamps will be adjusted to maintain relative timing")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
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
                let bundleToImport: ExportedHealthBundle
                if transposeDatesToToday {
                    bundleToImport = exportManager.transposeBundleDatesToToday(bundle)
                } else {
                    bundleToImport = bundle
                }
                try await exportManager.importData(bundleToImport)
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
                Section("Data source") {
                    Picker("Generation mode", selection: $exportManager.selectedManipulation) {
                        ForEach(DataManipulation.allCases, id: \.self) { manipulation in
                            VStack(alignment: .leading) {
                                Text(manipulation.rawValue)
                                Text(manipulation.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .tag(manipulation)
                        }
                    }
                    .pickerStyle(.menu)
                    
                    switch exportManager.selectedManipulation {
                    case .keepOriginal:
                        if let bundle = exportManager.lastExportedBundle {
                            HStack {
                                Label("\(bundle.sampleCount) samples", systemImage: "chart.line.uptrend.xyaxis")
                                Spacer()
                                Text(bundle.exportDate, style: .date)
                                    .foregroundStyle(.secondary)
                            }
                            Button(action: { showingFilePicker = true }) {
                                Label("Load different file", systemImage: "doc.badge.arrow.up")
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Sample file required", systemImage: "exclamationmark.triangle")
                                    .foregroundStyle(.orange)
                                Text("Load exported data to apply transformation patterns")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Button(action: { showingFilePicker = true }) {
                                Label("Load JSON file", systemImage: "doc.badge.arrow.up")
                            }
                        }
                        
                    case .smoothReplace:
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(.blue)
                                Text("Synthetic generation")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                            Text("Creates new health data with realistic patterns - no sample file needed")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                    case .generateMissing:
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "plus.circle")
                                    .foregroundStyle(.green)
                                Text("Fill gaps")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                            if let bundle = exportManager.lastExportedBundle {
                                Text("Will add data for empty categories in loaded file (\(bundle.sampleCount) samples)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Will generate complete dataset if no file is loaded")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if exportManager.lastExportedBundle == nil {
                            Button(action: { showingFilePicker = true }) {
                                Label("Load file (optional)", systemImage: "doc.badge.arrow.up")
                            }
                        }
                        
                    case .accessibilityMode:
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "figure.roll")
                                    .foregroundStyle(.purple)
                                Text("Accessibility mode")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                            Text("Converts step data to wheelchair pushes for accessibility testing")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                Section("Target date range") {
                    DatePicker("Start date", selection: $exportManager.targetStartDate, displayedComponents: [.date, .hourAndMinute])
                    DatePicker("End date", selection: $exportManager.targetEndDate, displayedComponents: [.date, .hourAndMinute])
                }
                
                Section("Generation settings") {
                    Picker("Stress preset", selection: $exportManager.selectedPreset) {
                        ForEach(GenerationPreset.allCases, id: \.self) { preset in
                            VStack(alignment: .leading) {
                                Text(preset.rawValue)
                                    .foregroundStyle(preset == .edgeCases ? .orange : .primary)
                                Text(preset.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .tag(preset)
                        }
                    }
                    .pickerStyle(.menu)
                    
                    if exportManager.selectedManipulation == .keepOriginal && exportManager.lastExportedBundle != nil {
                        Picker("Pattern type", selection: $exportManager.selectedPattern) {
                            ForEach(PatternType.allCases, id: \.self) { pattern in
                                Text(pattern.rawValue)
                                    .tag(pattern)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    
                    Stepper("Random seed: \(exportManager.patternSeed)", value: $exportManager.patternSeed, in: 0...100)
                    
                    Toggle("Include menstrual cycle data", isOn: $exportManager.includeMenstrualData)
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
                    .disabled(exportManager.isGenerating || 
                             (exportManager.selectedManipulation == .keepOriginal && exportManager.lastExportedBundle == nil))
                    
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
        Task {
            if exportManager.selectedManipulation == .keepOriginal && exportManager.lastExportedBundle != nil {
                // Use existing data with transformation
                guard let sourceBundle = exportManager.lastExportedBundle else { return }
                generatedBundle = await exportManager.generateTransformedData(from: sourceBundle)
            } else {
                // Generate synthetic data
                generatedBundle = await exportManager.generateSyntheticData()
            }
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @EnvironmentObject var exportManager: ExportManager
    @AppStorage("defaultDaysToExport") private var defaultDaysToExport = 7
    @AppStorage("includeEnhancedMetrics") private var includeEnhancedMetrics = true
    @State private var showingOverrideConfirmation = false
    @State private var pendingOverrideState = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Export defaults") {
                    Stepper("Days to export: \(defaultDaysToExport)", value: $defaultDaysToExport, in: 1...365)
                    Toggle("Include enhanced metrics", isOn: $includeEnhancedMetrics)
                }
                
                Section("Development override") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                                .font(.title2)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Override mode")
                                    .font(.headline)
                                    .foregroundStyle(.red)
                                Text("Enable all features on \(exportManager.actualPlatform)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        
                        Text("⚠️ WARNING: This override allows export and import functionality on both simulator and physical device. Use with extreme caution.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        
                        Toggle(isOn: Binding(
                            get: { exportManager.overrideModeEnabled },
                            set: { newValue in
                                pendingOverrideState = newValue
                                showingOverrideConfirmation = true
                            }
                        )) {
                            Text(exportManager.overrideModeEnabled ? "Override ACTIVE" : "Override disabled")
                                .foregroundStyle(exportManager.overrideModeEnabled ? .red : .primary)
                                .fontWeight(exportManager.overrideModeEnabled ? .bold : .regular)
                        }
                        .tint(.red)
                    }
                    .padding(.vertical, 8)
                }
                .listRowBackground(Color.red.opacity(0.05))
                
                Section("About") {
                    LabeledContent("Version", value: "1.1")
                    LabeledContent("Purpose", value: "Development testing")
                    LabeledContent("Platform", value: exportManager.actualPlatform)
                    if exportManager.overrideModeEnabled {
                        Label("Override mode active", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                    
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
            .alert("Enable override mode?", isPresented: $showingOverrideConfirmation) {
                Button("Cancel", role: .cancel) {
                    // Keep the current state
                }
                Button("Enable override", role: .destructive) {
                    exportManager.overrideModeEnabled = pendingOverrideState
                }
            } message: {
                if pendingOverrideState {
                    Text("This will enable ALL features (export and import) on \(exportManager.actualPlatform). This is intended for development only and may cause unexpected behavior.\n\nAre you absolutely sure?")
                } else {
                    Text("Disable override mode and return to normal platform-specific behavior?")
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(ExportManager())
}
