# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

HealthKit Exporter is a SwiftUI iOS app that exports HealthKit data from physical devices and imports it into the simulator for testing. It's designed as a companion tool for the Stillness app to help with development and testing using real health data.

## Build and run commands

```bash
# Open in Xcode
open HealthKitExporter.xcodeproj

# Build and run using Xcode - no command line build tools configured
# Target deployment: iOS 18.5+
```

## Architecture

### Core components

- **HealthKitExporterApp.swift**: Main app entry point with ExportManager as environment object
- **ExportManager.swift**: Main coordinator handling UI state, data transformation, and file operations
- **HealthDataExporter.swift**: Core HealthKit integration for reading/writing health data
- **HealthDataModels.swift**: Complete data models matching Stillness app format

### Data flow

1. **Export mode** (physical device): HealthDataExporter fetches from HealthKit → ExportedHealthBundle → JSON file
2. **Import mode** (simulator): JSON file → ExportedHealthBundle → HealthDataExporter saves to simulator HealthKit
3. **Pattern generation**: Original data → date transformation → pattern application → new ExportedHealthBundle

### Key patterns

- All HealthKit operations use async/await with proper error handling
- Platform detection using `#if targetEnvironment(simulator)` 
- Progress tracking through @Published properties
- File operations use DocumentGroup/FileDocument for sharing
- Pattern generation uses seeded random for reproducibility

## Data types supported

- Heart rate, HRV, activity (steps/distance/calories), sleep, workouts
- Enhanced metrics: respiratory rate, blood oxygen, skin temperature (iOS 16/17+)
- Import limitations: some metrics are read-only in HealthKit (resting HR, skin temp)

## Key considerations

- App requires HealthKit entitlements and privacy usage descriptions
- Enhanced metrics availability depends on iOS version and device capabilities
- Import functionality only works in simulator due to HealthKit write permissions
- Data format matches Stillness app's internal models for compatibility