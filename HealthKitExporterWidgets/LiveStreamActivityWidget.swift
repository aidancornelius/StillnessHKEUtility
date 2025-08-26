//
//  LiveStreamActivityWidget.swift
//  HealthKitExporter
//
//  Live Activity widget UI for streaming health data
//

import SwiftUI
import WidgetKit
import ActivityKit

struct LiveStreamActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveStreamActivityAttributes.self) { context in
            // Lock screen / banner UI
            LiveStreamLockScreenView(context: context)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.black.opacity(0.95))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(.green.opacity(0.3), lineWidth: 1)
                        )
                )
                .activityBackgroundTint(Color.black)
                .activitySystemActionForegroundColor(Color.green)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI
                DynamicIslandExpandedRegion(.leading) {
                    Label("Live", systemImage: "dot.radiowaves.left.and.right")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 4) {
                        Text(context.state.scenario)
                            .font(.headline)
                        HStack(spacing: 16) {
                            if let hr = context.state.lastHeartRate {
                                VStack(spacing: 2) {
                                    Image(systemName: "heart.fill")
                                        .foregroundStyle(.red)
                                        .font(.caption)
                                    Text("\(Int(hr))")
                                        .font(.system(.footnote, design: .monospaced))
                                }
                            }
                            if let hrv = context.state.lastHRV {
                                VStack(spacing: 2) {
                                    Image(systemName: "waveform.path.ecg")
                                        .foregroundStyle(.blue)
                                        .font(.caption)
                                    Text("\(Int(hrv))")
                                        .font(.system(.footnote, design: .monospaced))
                                }
                            }
                        }
                    }
                }
                
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(context.state.totalSamples)")
                            .font(.system(.caption, design: .monospaced))
                        Text("samples")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Image(systemName: context.state.isStreaming ? "circle.fill" : "circle")
                            .foregroundStyle(context.state.isStreaming ? .green : .gray)
                            .font(.caption2)
                        Text(context.state.streamingStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(context.state.lastUpdateTime, style: .time)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .foregroundStyle(.green)
            } compactTrailing: {
                if let hr = context.state.lastHeartRate {
                    Text("\(Int(hr))")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.red)
                }
            } minimal: {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .foregroundStyle(.green)
            }
            .widgetURL(URL(string: "healthkitexporter://livestream"))
            .keylineTint(.green)
        }
    }
}

struct LiveStreamLockScreenView: View {
    let context: ActivityViewContext<LiveStreamActivityAttributes>
    
    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(context.state.isStreaming ? .green : .orange)
                        .frame(width: 10, height: 10)
                        .overlay(
                            Circle()
                                .stroke(.white.opacity(0.3), lineWidth: 1)
                        )
                    Text("LIVE STREAMING")
                        .font(.system(.headline, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                }
                
                Text(context.state.scenario.uppercased())
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.medium)
                    .foregroundStyle(.green)
                
                Text(context.state.streamingStatus.uppercased())
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.8))
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 8) {
                if let hr = context.state.lastHeartRate {
                    HStack(spacing: 6) {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                        Text("\(Int(hr))")
                            .font(.system(.title2, design: .monospaced))
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                        Text("BPM")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                
                if let hrv = context.state.lastHRV {
                    HStack(spacing: 6) {
                        Image(systemName: "waveform.path.ecg")
                            .foregroundStyle(.cyan)
                            .font(.caption)
                        Text("\(Int(hrv))")
                            .font(.system(.title2, design: .monospaced))
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                        Text("MS")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                
                Text("\(context.state.totalSamples) SAMPLES")
                    .font(.system(.caption2, design: .monospaced))
                    .fontWeight(.medium)
                    .foregroundStyle(.green.opacity(0.9))
            }
        }
        .padding(.horizontal, 4)
    }
}