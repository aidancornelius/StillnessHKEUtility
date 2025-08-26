//
//  ExportView.swift
//  HealthKitExporter
//
//  View for exporting health data from device
//

import SwiftUI

struct ExportView: View {
    @EnvironmentObject var exportManager: ExportManager
    @State private var showingExporter = false
    @State private var exportedBundle: ExportedHealthBundle?
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Date range") {
                    DateRangePickerView(
                        startDate: $exportManager.sourceStartDate,
                        endDate: $exportManager.sourceEndDate
                    )
                    
                    QuickDateRangeButtons(
                        startDate: $exportManager.sourceStartDate,
                        endDate: $exportManager.sourceEndDate
                    )
                }
                
                Section("Data types") {
                    DataTypeSelectionView(selectedTypes: $exportManager.selectedDataTypes)
                }
                
                Section("Export") {
                    if exportManager.isExporting {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(exportManager.exportStatus)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            
                            ProgressView(value: exportManager.exportProgress)
                                .progressViewStyle(.linear)
                        }
                    } else {
                        Button(action: exportData) {
                            Label("Export from device", systemImage: "iphone.and.arrow.forward")
                        }
                        .disabled(exportManager.selectedDataTypes.isEmpty)
                    }
                    
                    if let bundle = exportedBundle {
                        Button(action: { showingExporter = true }) {
                            Label("Save \(bundle.sampleCount) samples", systemImage: "square.and.arrow.down")
                        }
                    }
                }
                
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
                
                if let bundle = exportedBundle {
                    ExportSummarySection(bundle: bundle)
                }
            }
            .navigationTitle("Export health data")
            .fileExporter(
                isPresented: $showingExporter,
                document: exportedBundle.map { HealthDataDocument(bundle: $0) },
                contentType: .json,
                defaultFilename: "health_export_\(Date().ISO8601Format()).json"
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
    
    private func exportData() {
        Task {
            do {
                exportedBundle = try await exportManager.exportOriginalData()
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Quick Date Range Buttons

struct QuickDateRangeButtons: View {
    @Binding var startDate: Date
    @Binding var endDate: Date
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(quickRanges, id: \.label) { range in
                    Button(range.label) {
                        startDate = range.startDate
                        endDate = range.endDate
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }
    
    private var quickRanges: [(label: String, startDate: Date, endDate: Date)] {
        let now = Date()
        let calendar = Calendar.current
        
        return [
            ("Today", calendar.startOfDay(for: now), now),
            ("Yesterday", 
             calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))!,
             calendar.startOfDay(for: now)),
            ("Last 7 days", 
             calendar.date(byAdding: .day, value: -7, to: now)!,
             now),
            ("Last 30 days",
             calendar.date(byAdding: .day, value: -30, to: now)!,
             now),
            ("Last 3 months",
             calendar.date(byAdding: .month, value: -3, to: now)!,
             now),
            ("Last year",
             calendar.date(byAdding: .year, value: -1, to: now)!,
             now)
        ]
    }
}

// MARK: - Export Summary Section

struct ExportSummarySection: View {
    let bundle: ExportedHealthBundle
    
    var body: some View {
        Section("Export summary") {
            LabeledContent("Total samples", value: "\(bundle.sampleCount)")
            
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
            
            if let restingHR = bundle.restingHeartRate {
                LabeledContent("Resting HR", value: "\(Int(restingHR)) bpm")
            }
            
            if let respiratory = bundle.respiratoryRate, !respiratory.isEmpty {
                LabeledContent("Respiratory rate", value: "\(respiratory.count) samples")
            }
            
            if let oxygen = bundle.bloodOxygen, !oxygen.isEmpty {
                LabeledContent("Blood oxygen", value: "\(oxygen.count) samples")
            }
            
            if let temp = bundle.skinTemperature, !temp.isEmpty {
                LabeledContent("Skin temperature", value: "\(temp.count) samples")
            }
        }
    }
}

#Preview {
    NavigationStack {
        ExportView()
            .environmentObject(ExportManager())
    }
}