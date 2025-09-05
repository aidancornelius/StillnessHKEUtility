# HealthKit Exporter

A tool app that exports real HealthKit data (heart rate, steps, sleep, workouts, etc.) from your physical iPhone, and paired Apple Watch into a JSON file, then imports that data into the iOS Simulator's HealthKit store. It can also generate synthetic health data patterns based on real samples.

Useful when developing health apps you can't test with realistic data in the Simulator since it lacks real sensors. This tool lets you capture your actual health metrics from your devices and use them in the Simulator for development and testing, ensuring your app handles real-world-ish data correctly before deployment (good for automated testing).

## Features

The app basically does what it says on the tin:

Adjusts available tabs based on whether you're running on a physical device or simulator. 
  - On devices, you see Export,Generate, Network Stream, and Settings tabs. 
  - On simulators, you get Import instead of Export, plus Live Generate for continuous data generation.
  - An override mode allows all features on any platform for development testing.

### Export

Extracts real HealthKit data from your physical iPhone/Apple Watch/etc. You select a date range (with quick presets like "Last 7 days"), choose which health metrics to include, then export everything to a JSON file. Shows a summary of collected samples before saving.

### Import

Loads previously exported JSON files into the simulator's HealthKit database. Features automatic date transposition to make historical data appear recent, perfect for testing current date scenarios. Shows preview of data categories and sample counts before importing.

### Generator

Creates synthetic health data based on patterns and presets. Can transform existing data with patterns (stable, trending, spiky) or generate new datasets. Includes stress presets, and modes like wheelchair testing. Uses seeded randomisation for
reproducible test scenarios.

### Livestream

Continuously generates health data in real-time, simulating ongoing sensor readings. Choose scenarios like exercise, sleep, or stress tests, with data generated at configurable intervals. Automatically broadcasts to connected simulators over the network and includes safety limits to prevent runaway generation.

### Networkstream

Enables real-time streaming between physical devices and simulators over local network. Devices broadcast live health data that simulators can discover and receive. Includes HealthKit verification to confirm data is properly saved, recent sample display, and connection statistics. Handles local network permissions on devices.

## Requirements

- iOS 18.5+
- iPhone
- HealthKit access

## Setup

1. Open `HealthKitExporter.xcodeproj` in Xcode
2. Select your development team in project settings
3. Run it wherever you like
