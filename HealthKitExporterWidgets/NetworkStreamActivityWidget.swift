//
//  NetworkStreamActivityWidget.swift
//  HealthKitExporterWidgets
//
//  Airport-themed Live Activity Widget for network streaming
//

import ActivityKit
import WidgetKit
import SwiftUI

// Local copy of attributes for widget - needs to match main app
struct NetworkStreamActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var isConnected: Bool
        var connectionType: String
        var deviceName: String?
        var totalSamples: Int
        var samplesPerMinute: Double
        var lastSampleTime: Date?
        var lastHeartRate: Double?
        var lastHRV: Double?
        var lastScenario: String?
        var status: String
        var healthKitSaves: Int
        var lastUpdateTime: Date
        var flightNumber: String
        var gate: String
        var destination: String
    }
    
    var startTime: Date
    var mode: String
}

struct NetworkStreamActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NetworkStreamActivityAttributes.self) { context in
            // Lock screen/banner UI
            LockScreenLiveActivityView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI
                DynamicIslandExpandedRegion(.leading) {
                    HStack {
                        Image(systemName: "airplane.departure")
                            .foregroundColor(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(context.state.flightNumber)
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            Text("GATE \(context.state.gate)")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(context.state.status)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(statusColor(context.state.status))
                        Text("\(context.state.totalSamples) samples")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("→ \(context.state.destination)")
                                .font(.caption)
                                .foregroundColor(.primary)
                            
                            if let lastSample = context.state.lastSampleTime {
                                Text("Last: \(lastSample, style: .time)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 4) {
                            if let hr = context.state.lastHeartRate {
                                Text("♥︎ \(String(format: "%.0f", hr))")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                            
                            if context.state.samplesPerMinute > 0 {
                                Text("\(String(format: "%.1f", context.state.samplesPerMinute))/min")
                                    .font(.caption2)
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: context.attributes.mode == "broadcast" ? "airplane.departure" : "airplane.arrival")
                    .foregroundColor(.orange)
            } compactTrailing: {
                Text(context.state.status)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(statusColor(context.state.status))
            } minimal: {
                Image(systemName: context.attributes.mode == "broadcast" ? "antenna.radiowaves.left.and.right" : "wifi.router")
                    .foregroundColor(context.state.isConnected ? .green : .orange)
            }
        }
    }
    
    private func statusColor(_ status: String) -> Color {
        switch status.uppercased() {
        case "IN FLIGHT", "STREAMING":
            return .green
        case "BOARDING", "CONNECTING":
            return .orange
        case "DELAYED", "ERROR":
            return .red
        case "ARRIVED", "COMPLETE":
            return .blue
        default:
            return .primary
        }
    }
}

struct LockScreenLiveActivityView: View {
    let context: ActivityViewContext<NetworkStreamActivityAttributes>
    
    var body: some View {
        VStack(spacing: 12) {
            // Airport board header
            HStack {
                Image(systemName: context.attributes.mode == "broadcast" ? "airplane.departure" : "airplane.arrival")
                    .foregroundColor(.orange)
                    .font(.title2)
                
                Text(context.attributes.mode == "broadcast" ? "DEPARTURES" : "ARRIVALS")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text(context.state.flightNumber)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.orange)
            }
            
            // Flight info row
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("GATE")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(context.state.gate)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                VStack(alignment: .center, spacing: 4) {
                    Text("DESTINATION")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(context.state.destination)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("STATUS")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(context.state.status.uppercased())
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(statusColor(context.state.status))
                }
            }
            
            // Health data cargo info
            HStack {
                Image(systemName: "heart.fill")
                    .foregroundColor(.red)
                    .font(.caption)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Health Data Cargo")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 12) {
                        Text("\(context.state.totalSamples) samples")
                            .font(.caption)
                            .fontWeight(.medium)
                        
                        if context.state.samplesPerMinute > 0 {
                            Text("•")
                                .foregroundColor(.secondary)
                            Text("\(String(format: "%.1f", context.state.samplesPerMinute))/min")
                                .font(.caption)
                        }
                        
                        if let hr = context.state.lastHeartRate {
                            Text("•")
                                .foregroundColor(.secondary)
                            Text("HR \(String(format: "%.0f", hr))")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }
                
                Spacer()
                
                if context.state.healthKitSaves > 0 {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("SAVED")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("\(context.state.healthKitSaves)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.green)
                    }
                }
            }
            .padding(.top, 4)
        }
        .padding()
        .background(
            LinearGradient(
                colors: [Color(.systemBackground), Color(.secondarySystemBackground)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .colorScheme(.dark)
    }
    
    private func statusColor(_ status: String) -> Color {
        switch status.uppercased() {
        case "IN FLIGHT", "STREAMING":
            return .green
        case "BOARDING", "CONNECTING":
            return .orange
        case "DELAYED", "ERROR":
            return .red
        case "ARRIVED", "COMPLETE":
            return .blue
        default:
            return .primary
        }
    }
}

#Preview("Lock Screen", as: .content, using: NetworkStreamActivityAttributes(
    startTime: Date(),
    mode: "broadcast"
)) {
    NetworkStreamActivityWidget()
} contentStates: {
    NetworkStreamActivityAttributes.ContentState(
        isConnected: true,
        connectionType: "Broadcasting",
        deviceName: "iPhone Pro",
        totalSamples: 142,
        samplesPerMinute: 12.5,
        lastSampleTime: Date(),
        lastHeartRate: 72,
        lastHRV: 45.2,
        lastScenario: "Resting",
        status: "IN FLIGHT",
        healthKitSaves: 142,
        lastUpdateTime: Date(),
        flightNumber: "HK815",
        gate: "B12",
        destination: "Simulator"
    )
}
