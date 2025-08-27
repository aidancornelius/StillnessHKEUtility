//
//  LiveStreamActivityAttributes.swift
//  HealthKitExporter
//
//  Live Activity support for streaming health data
//

import Foundation
import ActivityKit

struct LiveStreamActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var isStreaming: Bool
        var scenario: String
        var totalSamples: Int
        var lastHeartRate: Double?
        var lastHRV: Double?
        var streamingStatus: String
        var detailedStatus: String
        var backgroundProcessingActive: Bool
        var lastUpdateTime: Date
    }
    
    var startTime: Date
    var interval: TimeInterval
}