//
//  DateRangePickerView.swift
//  HealthKitExporter
//
//  View for selecting date ranges
//

import SwiftUI

struct DateRangePickerView: View {
    @Binding var startDate: Date
    @Binding var endDate: Date
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DatePicker(
                "Start date",
                selection: $startDate,
                in: ...endDate,
                displayedComponents: [.date, .hourAndMinute]
            )
            
            DatePicker(
                "End date",
                selection: $endDate,
                in: startDate...,
                displayedComponents: [.date, .hourAndMinute]
            )
            
            HStack {
                Image(systemName: "calendar")
                    .foregroundStyle(.secondary)
                Text(durationText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)
        }
    }
    
    private var durationText: String {
        let components = Calendar.current.dateComponents(
            [.day, .hour],
            from: startDate,
            to: endDate
        )
        
        var parts: [String] = []
        
        if let days = components.day, days > 0 {
            parts.append("\(days) day\(days == 1 ? "" : "s")")
        }
        
        if let hours = components.hour, hours > 0 {
            parts.append("\(hours) hour\(hours == 1 ? "" : "s")")
        }
        
        return parts.isEmpty ? "Invalid range" : parts.joined(separator: ", ")
    }
}

#Preview {
    Form {
        DateRangePickerView(
            startDate: .constant(Date().addingTimeInterval(-86400)),
            endDate: .constant(Date())
        )
    }
}