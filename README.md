# HealthKit Exporter

A tool app for Stillness that exports, transforms, and imports HealthKit data for testing purposes.

## Features

The app basically does what it says on the tin:

### Real device mode
When running on a physical device with HK data:
- Export heart rate, HRV, activity, sleep, workouts, and enhanced metrics
- Select custom date ranges or use quick presets
- Export to JSON format for use in simulator testing

### Simulator mode
When running in the simulator:
- Import JSON files directly into simulator's HealthKit database ('Share' the JSON file to the simulator)
- Populate simulator with real device data for testing (you may need to ask it twice, for some reason)
- Preview data before importing
- Real-time import progress

### Generate test patterns (largely useless) 
- Transform data to different date ranges (e.g., 2022 data → 2025)
- Apply pattern modifications:
  - Similar pattern: Minor variations
  - Amplified: Increase stress levels by 20-40%
  - Reduced: Decrease stress levels by 20-40%
  - Inverted: Flip high and low stress periods
  - Random: Add random variations
- Seed-based generation for reproducible results (ha)

## Requirements

- iOS 18.5+
- iPhone
- HealthKit access

## Setup

1. Open `HealthKitExporter.xcodeproj` in Xcode
2. Select your development team in project settings
3. Run it wherever you like

## Usage

### On a physical device to export data

1. Run app on physical device
2. Go to "Export data" tab
3. Select date range
4. Choose data types to export
5. Tap "Export from device"
6. Save the JSON file

### In simulator to import data

1. Run app in simulator
2. Go to "Import data" tab
3. Tap "Load JSON file"
4. Select an exported data file
5. Review the data preview
6. Tap "Import to simulator"
7. Data is now available in simulator's HealthKit

### Generating test data

1. Go to "Generate patterns" tab
2. Load an exported JSON file or use last export
3. Set target date range for transformation
4. Choose pattern type
5. Tap "Generate test data"
6. Export the transformed data

## Data format

Exported data follows the same structure as Stillness's internal models, making it easy to import for testing.
