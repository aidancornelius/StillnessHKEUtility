//
//  DataTypeSelectionView.swift
//  HealthKitExporter
//
//  View for selecting which health data types to export
//

import SwiftUI

struct DataTypeSelectionView: View {
    @Binding var selectedTypes: Set<HealthDataType>
    
    var body: some View {
        ForEach(HealthDataType.allCases, id: \.self) { dataType in
            Toggle(isOn: binding(for: dataType)) {
                Label {
                    VStack(alignment: .leading) {
                        Text(dataType.rawValue)
                        if dataType.isEnhanced {
                            Text("Enhanced metric")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } icon: {
                    Image(systemName: dataType.icon)
                        .foregroundStyle(selectedTypes.contains(dataType) ? .accent : .secondary)
                }
            }
        }
    }
    
    private func binding(for dataType: HealthDataType) -> Binding<Bool> {
        Binding(
            get: { selectedTypes.contains(dataType) },
            set: { isSelected in
                if isSelected {
                    selectedTypes.insert(dataType)
                } else {
                    selectedTypes.remove(dataType)
                }
            }
        )
    }
}

#Preview {
    Form {
        DataTypeSelectionView(selectedTypes: .constant([.heartRate, .hrv]))
    }
}