//
//  LiveStreamView.swift
//  HealthKitExporter
//
//  Live data streaming interface for continuous health data generation
//

import SwiftUI

struct LiveStreamView: View {
    @EnvironmentObject var exportManager: ExportManager
    @StateObject private var liveStreamManager = LiveStreamManager()
    @State private var showingFilePicker = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            Form {
                // Source Data Section
                Section("Source data") {
                    if let bundle = liveStreamManager.sourceBundle ?? exportManager.lastExportedBundle {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label("\(bundle.sampleCount) samples", systemImage: "chart.line.uptrend.xyaxis")
                                Spacer()
                                Text(bundle.exportDate, style: .date)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Text("HR avg: \(averageHeartRate(from: bundle), specifier: "%.1f") BPM")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("HRV avg: \(averageHRV(from: bundle), specifier: "%.1f") ms")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Button(action: { showingFilePicker = true }) {
                            Label("Load different data", systemImage: "doc.badge.arrow.up")
                        }
                        .disabled(liveStreamManager.isStreaming)
                        
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("No source data loaded")
                                .foregroundStyle(.secondary)
                            Text("Load exported health data to use as baseline for streaming patterns.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Button(action: { showingFilePicker = true }) {
                            Label("Load source data", systemImage: "doc.badge.arrow.up")
                        }
                    }
                }
                
                // Streaming Configuration Section
                Section("Streaming configuration") {
                    Picker("Scenario", selection: $liveStreamManager.currentScenario) {
                        ForEach(StreamingScenario.allCases, id: \.self) { scenario in
                            VStack(alignment: .leading) {
                                Text(scenario.rawValue)
                                Text(scenario.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .tag(scenario)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(liveStreamManager.isStreaming)
                    
                    HStack {
                        Text("Interval")
                        Spacer()
                        Picker("Interval", selection: $liveStreamManager.streamingInterval) {
                            Text("15 seconds").tag(15.0)
                            Text("30 seconds").tag(30.0)
                            Text("1 minute").tag(60.0)
                            Text("2 minutes").tag(120.0)
                            Text("5 minutes").tag(300.0)
                        }
                        .pickerStyle(.menu)
                    }
                    .disabled(liveStreamManager.isStreaming)
                }
                
                // Live Monitoring Section
                if liveStreamManager.isStreaming || liveStreamManager.totalSamplesGenerated > 0 {
                    Section("Live monitoring") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Circle()
                                    .fill(liveStreamManager.isStreaming ? .green : .gray)
                                    .frame(width: 8, height: 8)
                                Text(liveStreamManager.streamingStatus)
                                    .font(.subheadline)
                            }
                            
                            if liveStreamManager.isStreaming {
                                HStack {
                                    Text("Samples generated:")
                                    Spacer()
                                    Text("\(liveStreamManager.totalSamplesGenerated)")
                                        .font(.monospaced(.body)())
                                }
                                .font(.caption)
                            }
                        }
                        
                        // Last generated values
                        if !liveStreamManager.lastGeneratedValues.isEmpty {
                            ForEach(Array(liveStreamManager.lastGeneratedValues.keys.sorted()), id: \.self) { key in
                                if let value = liveStreamManager.lastGeneratedValues[key] {
                                    HStack {
                                        Text(key)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text("\(value, specifier: "%.1f")")
                                            .font(.monospaced(.caption)())
                                            .foregroundStyle(.primary)
                                    }
                                }
                            }
                        }
                    }
                }
                
                // Streaming Controls Section
                Section("Streaming controls") {
                    if liveStreamManager.isStreaming {
                        Button(action: { liveStreamManager.stopStreaming() }) {
                            Label("Stop streaming", systemImage: "stop.fill")
                                .foregroundStyle(.red)
                        }
                        
                        Button(action: { liveStreamManager.pauseStreaming() }) {
                            Label("Pause streaming", systemImage: "pause.fill")
                                .foregroundStyle(.orange)
                        }
                        
                        Button(action: { liveStreamManager.resumeStreaming() }) {
                            Label("Resume streaming", systemImage: "play.fill")
                                .foregroundStyle(.blue)
                        }
                    } else {
                        Button(action: startStreaming) {
                            Label("Start streaming", systemImage: "play.fill")
                        }
                        .disabled(liveStreamManager.sourceBundle == nil && exportManager.lastExportedBundle == nil)
                    }
                }
                
                // Safety Information Section
                Section("Safety limits") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Max samples per hour:")
                            Spacer()
                            Text("3,600")
                                .font(.monospaced(.caption)())
                        }
                        
                        HStack {
                            Text("Max total samples:")
                            Spacer()
                            Text("10,000")
                                .font(.monospaced(.caption)())
                        }
                        
                        Text("Streaming will automatically stop when limits are reached to prevent excessive data generation.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Live streaming")
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        loadSourceData(url)
                    }
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
            .onAppear {
                // Use last exported bundle if no source data is loaded
                if liveStreamManager.sourceBundle == nil {
                    liveStreamManager.sourceBundle = exportManager.lastExportedBundle
                }
            }
        }
    }
    
    private func startStreaming() {
        // Ensure we have source data
        if liveStreamManager.sourceBundle == nil {
            liveStreamManager.sourceBundle = exportManager.lastExportedBundle
        }
        
        liveStreamManager.startStreaming()
        errorMessage = nil
    }
    
    private func loadSourceData(_ url: URL) {
        do {
            _ = url.startAccessingSecurityScopedResource()
            defer { url.stopAccessingSecurityScopedResource() }
            
            liveStreamManager.sourceBundle = try exportManager.loadFromFile(url)
            errorMessage = nil
        } catch {
            errorMessage = "Failed to load file: \(error.localizedDescription)"
        }
    }
    
    private func averageHeartRate(from bundle: ExportedHealthBundle) -> Double {
        guard !bundle.heartRate.isEmpty else { return 0 }
        return bundle.heartRate.map(\.value).reduce(0, +) / Double(bundle.heartRate.count)
    }
    
    private func averageHRV(from bundle: ExportedHealthBundle) -> Double {
        guard !bundle.hrv.isEmpty else { return 0 }
        return bundle.hrv.map(\.value).reduce(0, +) / Double(bundle.hrv.count)
    }
}

#Preview {
    NavigationStack {
        LiveStreamView()
            .environmentObject(ExportManager())
    }
}