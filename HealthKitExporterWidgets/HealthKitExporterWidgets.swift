//
//  HealthKitExporterWidgets.swift
//  HealthKitExporterWidgets
//
//  Widget bundle for HealthKit Exporter Live Activities
//

import SwiftUI
import WidgetKit

@main
struct HealthKitExporterWidgets: WidgetBundle {
    var body: some Widget {
        LiveStreamActivityWidget()
        NetworkStreamActivityWidget()
    }
}