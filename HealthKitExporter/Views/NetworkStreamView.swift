//
//  NetworkStreamView.swift
//  HealthKitExporter
//
//  Real-time streaming UI between device and simulator
//

import SwiftUI
import Network

struct NetworkStreamView: View {
    @ObservedObject var liveStreamManager: LiveStreamManager
    @StateObject private var networkManager: NetworkStreamingManager
    
    private var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }
    
    init(liveStreamManager: LiveStreamManager) {
        self.liveStreamManager = liveStreamManager
        self._networkManager = StateObject(wrappedValue: liveStreamManager.networkStreamingManager)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                if isSimulator {
                    Section("Receive Mode (Simulator)") {
                        simulatorModeSection
                    }
                    
                    Section("Data Verification") {
                        dataVerificationSection
                    }
                    
                    Section("Recent Samples") {
                        recentSamplesSection
                    }
                } else {
                    Section("Broadcast Mode (Device)") {
                        deviceModeSection
                    }
                }
                
                Section("Statistics") {
                    statisticsSection
                }
            }
            .navigationTitle("Network streaming")
        }
    }
    
    private var deviceModeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(.blue)
                Text("Broadcasting live health data to simulators")
                    .font(.subheadline)
                Spacer()
            }
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Server Status")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(networkManager.streamingStatus)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(networkManager.isServerRunning ? .green : .primary)
                }
                
                Spacer()
                
                HStack(spacing: 8) {
                    Button(networkManager.isServerRunning ? "Stop Broadcasting" : "Start Broadcasting") {
                        if networkManager.isServerRunning {
                            liveStreamManager.stopNetworkStreaming()
                        } else {
                            liveStreamManager.startNetworkStreaming()
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    if networkManager.streamingStatus.contains("permission") || networkManager.streamingStatus.contains("NoAuth") {
                        Button("Fix Permissions") {
                            networkManager.requestLocalNetworkPermission()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
            }
            
            if networkManager.isClientConnected {
                HStack {
                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                    Text("Simulator connected - streaming data")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            } else if networkManager.isServerRunning {
                HStack {
                    Circle()
                        .fill(.orange)
                        .frame(width: 8, height: 8)
                    Text("Waiting for simulator to connect")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            
            // Show permissions help if needed
            if networkManager.streamingStatus.contains("permission") || networkManager.streamingStatus.contains("NoAuth") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Text("Local Network Permission Required")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    
                    Text("To broadcast health data, this app needs permission to access your local network. Go to Settings > Privacy & Security > Local Network > HealthKitExporter and enable access.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(Color(.systemOrange).opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding(.vertical, 4)
    }
    
    private var simulatorModeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "wifi.router")
                    .foregroundStyle(.orange)
                Text("Receiving live health data from devices")
                    .font(.subheadline)
                Spacer()
            }
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Connection Status")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(networkManager.connectionStatus)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(networkManager.isClientConnected ? .green : .primary)
                }
                
                Spacer()
                
                if networkManager.isClientConnected {
                    Button("Disconnect") {
                        liveStreamManager.stopReceivingNetworkStream()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    Button("Discover") {
                        liveStreamManager.startReceivingNetworkStream()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            
            if !networkManager.discoveredDevices.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Broadcasting Devices")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    ForEach(networkManager.discoveredDevices) { device in
                        Button(action: {
                            networkManager.connectToDevice(device)
                        }) {
                            HStack {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                    .foregroundStyle(.blue)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(device.name)
                                        .fontWeight(.medium)
                                    Text("Tap to connect")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.right.circle.fill")
                                    .foregroundStyle(.blue)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(.systemGray6))
                            .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private var statisticsSection: some View {
        VStack(spacing: 12) {
            if isSimulator {
                // Simulator - show received data
                VStack(alignment: .center, spacing: 8) {
                    Text("Data Received")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(networkManager.totalDataReceived)")
                        .font(.system(.title, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundStyle(.orange)
                    Text("health samples")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                // Device - show sent data
                VStack(alignment: .center, spacing: 8) {
                    Text("Data Broadcasted")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(networkManager.totalDataSent)")
                        .font(.system(.title, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundStyle(.blue)
                    Text("health samples")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            
            if networkManager.isServerRunning || networkManager.isClientConnected {
                HStack {
                    Circle()
                        .fill(.green)
                        .frame(width: 6, height: 6)
                    Text(isSimulator ? "Receiving real-time data" : "Broadcasting real-time data")
                        .font(.caption)
                        .foregroundStyle(.green)
                    Spacer()
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    @State private var healthKitVerification: HealthKitVerificationResult?
    @State private var isVerifying = false
    
    private var dataVerificationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "checkmark.shield")
                    .foregroundStyle(.blue)
                Text("HealthKit Integration")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Button("Verify Now") {
                    Task {
                        isVerifying = true
                        healthKitVerification = await networkManager.verifyHealthKitData()
                        isVerifying = false
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isVerifying)
            }
            
            if isVerifying {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Checking HealthKit...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            if let verification = healthKitVerification {
                VStack(spacing: 8) {
                    if let error = verification.error {
                        Text("Error: \(error)")
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else {
                        VStack(spacing: 6) {
                            HStack {
                                Text("Saved to HealthKit:")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(networkManager.healthKitSaveCount) samples")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.green)
                            }
                            
                            HStack {
                                Text("Heart Rate in HealthKit:")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(verification.totalHeartRateCount)")
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            
                            HStack {
                                Text("HRV in HealthKit:")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(verification.totalHRVCount)")
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            
                            if !verification.recentHeartRateValues.isEmpty {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Recent HR values:")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(verification.recentHeartRateValues.map { String(format: "%.0f", $0) }.joined(separator: ", "))
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                }
                .padding(8)
                .background(Color(.systemGray6))
                .cornerRadius(6)
            }
            
            // Show errors if any
            if !networkManager.healthKitErrors.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recent Errors:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(networkManager.healthKitErrors.indices, id: \.self) { index in
                        Text("• \(networkManager.healthKitErrors[index])")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }
                .padding(8)
                .background(Color(.systemRed).opacity(0.1))
                .cornerRadius(6)
            }
        }
        .padding(.vertical, 4)
    }
    
    private var recentSamplesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if networkManager.recentSamples.isEmpty {
                Text("No samples received yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(networkManager.recentSamples) { sample in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                if let hr = sample.heartRate {
                                    Text("HR: \(String(format: "%.0f", hr))")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                }
                                if let hrv = sample.hrv {
                                    Text("HRV: \(String(format: "%.1f", hrv))")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                }
                            }
                            
                            HStack {
                                Text(sample.scenario)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(sample.timestamp, style: .time)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        Image(systemName: sample.savedToHealthKit ? "checkmark.circle.fill" : "clock")
                            .foregroundStyle(sample.savedToHealthKit ? .green : .orange)
                            .font(.caption)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(sample.savedToHealthKit ? Color(.systemGreen).opacity(0.1) : Color(.systemOrange).opacity(0.1))
                    .cornerRadius(6)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NetworkStreamView(liveStreamManager: LiveStreamManager())
}