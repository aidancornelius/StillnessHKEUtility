//
//  NetworkStreamingManager.swift
//  HealthKitExporter
//
//  Real-time health data streaming between device and simulator
//

import Foundation
import Network
import SwiftUI
import HealthKit
import ActivityKit

// Local NetworkStreamActivityAttributes for Live Activity
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

@MainActor
class NetworkStreamingManager: ObservableObject {
    private var listener: NWListener?
    private var connection: NWConnection?
    private let serviceName = "_healthkitstream._tcp"
    private let port = NWEndpoint.Port(integerLiteral: 8080)
    
    @Published var isServerRunning = false
    @Published var isClientConnected = false
    @Published var discoveredDevices: [DiscoveredDevice] = []
    @Published var streamingStatus = "Ready"
    @Published var connectionStatus = "Disconnected"
    @Published var totalDataSent = 0
    @Published var totalDataReceived = 0
    @Published var lastReceivedPacket: HealthDataPacket?
    @Published var healthKitSaveCount = 0
    @Published var healthKitErrors: [String] = []
    @Published var recentSamples: [ReceivedSample] = []
    
    private var browser: NWBrowser?
    private let queue = DispatchQueue(label: "NetworkStreaming")
    private var testDataTimer: Timer?
    private var currentActivity: Activity<NetworkStreamActivityAttributes>?
    private var lastSentPacket: HealthDataPacket?
    private var sharedFlightNumber: String?
    
    // MARK: - Server Mode (Device)
    
    func requestLocalNetworkPermission() {
        // Trigger local network permission prompt by attempting a brief connection
        // This will show the permission dialog if not already granted
        let tempParameters = NWParameters.tcp
        tempParameters.includePeerToPeer = false
        
        do {
            let tempListener = try NWListener(using: tempParameters, on: .any)
            tempListener.start(queue: DispatchQueue.global())
            
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                tempListener.cancel()
            }
        } catch {
            print("Could not create temporary listener for permissions: \(error)")
        }
    }
    
    func startServer() {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        
        // Add Bonjour service advertisement
        let bonjourService = NWListener.Service(name: UIDevice.current.name, type: serviceName)
        // Remove peer-to-peer requirement to avoid multicast entitlement issues
        parameters.includePeerToPeer = false
        
        do {
            listener = try NWListener(using: parameters, on: port)
            listener?.service = bonjourService
            
            listener?.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    switch state {
                    case .ready:
                        self?.isServerRunning = true
                        self?.streamingStatus = "Broadcasting on local network"
                        print("✅ Server ready on port \(self?.port.rawValue ?? 0)")
                    case .failed(let error):
                        let errorString = self?.formatNetworkError(error) ?? "Unknown error"
                        self?.streamingStatus = "Server failed: \(errorString)"
                        self?.isServerRunning = false
                        print("❌ Server failed: \(error)")
                    case .cancelled:
                        self?.isServerRunning = false
                        self?.streamingStatus = "Server stopped"
                        print("⏹️ Server cancelled")
                    case .waiting(let error):
                        self?.streamingStatus = "Server waiting: \(self?.formatNetworkError(error) ?? "Unknown reason")"
                        print("⏳ Server waiting: \(error)")
                    default:
                        print("🔄 Server state: \(state)")
                    }
                }
            }
            
            listener?.newConnectionHandler = { [weak self] connection in
                print("📱 New connection from: \(connection.endpoint)")
                Task { @MainActor [weak self] in
                    await self?.handleNewConnection(connection)
                }
            }
            
            listener?.start(queue: queue)
            streamingStatus = "Starting server..."
            print("🚀 Starting health data broadcaster...")
            
        } catch {
            let errorString = formatNetworkError(error)
            streamingStatus = "Failed to start server: \(errorString)"
            print("💥 Failed to start server: \(error)")
        }
    }
    
    private func formatNetworkError(_ error: Error) -> String {
        if let nwError = error as? NWError {
            switch nwError {
            case .posix(let posixError):
                switch posixError {
                case .EADDRINUSE:
                    return "Port already in use"
                case .EACCES:
                    return "Permission denied - try restarting the app"
                case .ENETUNREACH:
                    return "Network unreachable"
                default:
                    return "Network error: \(posixError.rawValue)"
                }
            case .dns(let dnsError):
                switch dnsError {
                case -6555: // NoAuth error
                    return "Local network permission required - check Settings > Privacy & Security > Local Network"
                default:
                    return "DNS error: \(dnsError)"
                }
            default:
                return error.localizedDescription
            }
        }
        return error.localizedDescription
    }
    
    func stopServer() {
        stopTestDataTransmission()
        stopLiveActivity()
        listener?.cancel()
        connection?.cancel()
        listener = nil
        connection = nil
        isClientConnected = false
        streamingStatus = "Server stopped"
    }
    
    private func handleNewConnection(_ connection: NWConnection) async {
        DispatchQueue.main.async {
            self.connection = connection
            self.connectionStatus = "Client connecting..."
        }
        
        connection.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    self?.isClientConnected = true
                    self?.connectionStatus = "Client connected"
                    self?.streamingStatus = "Streaming to simulator"
                    self?.startTestDataTransmission()
                    self?.startBroadcastLiveActivity()
                case .cancelled, .failed:
                    self?.isClientConnected = false
                    self?.connectionStatus = "Client disconnected"
                    self?.streamingStatus = "Server ready - waiting for connections"
                    self?.stopTestDataTransmission()
                    self?.stopLiveActivity()
                    self?.connection = nil
                default:
                    break
                }
            }
        }
        
        connection.start(queue: queue)
        Task {
            await startReceivingData(on: connection)
        }
    }
    
    private func startTestDataTransmission() {
        // Send test health data every 5 seconds to verify connection
        testDataTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sendTestHealthData()
            }
        }
        print("🚀 Started test data transmission")
    }
    
    private func stopTestDataTransmission() {
        testDataTimer?.invalidate()
        testDataTimer = nil
        print("⏹️ Stopped test data transmission")
    }
    
    private func sendTestHealthData() {
        let testPacket = HealthDataPacket(
            timestamp: Date(),
            heartRate: Double.random(in: 60...100),
            hrv: Double.random(in: 20...80),
            scenario: "Test Data"
        )
        sendHealthData(testPacket)
    }
    
    func sendHealthData(_ data: HealthDataPacket) {
        guard let connection = connection, isClientConnected else { return }
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let jsonData = try encoder.encode(data)
            
            // Add message length header (4 bytes)
            var lengthData = Data()
            let length = UInt32(jsonData.count)
            lengthData.append(contentsOf: withUnsafeBytes(of: length.bigEndian) { Data($0) })
            
            // Send length first, then data
            connection.send(content: lengthData, completion: .contentProcessed { _ in })
            connection.send(content: jsonData, completion: .contentProcessed { [weak self] error in
                DispatchQueue.main.async {
                    if error == nil {
                        self?.totalDataSent += 1
                        self?.streamingStatus = "Broadcasting data (\(self?.totalDataSent ?? 0) samples)"
                        self?.lastSentPacket = data
                        self?.updateLiveActivity()
                        print("📤 Sent health data: HR=\(data.heartRate ?? 0), HRV=\(data.hrv ?? 0)")
                    } else {
                        print("❌ Failed to send data: \(error?.localizedDescription ?? "unknown")")
                    }
                }
            })
            
        } catch {
            print("Failed to send health data: \(error)")
        }
    }
    
    // MARK: - Client Mode (Simulator)
    
    func startDiscovery() {
        let parameters = NWParameters()
        parameters.includePeerToPeer = false
        
        browser = NWBrowser(for: .bonjourWithTXTRecord(type: serviceName, domain: nil), using: parameters)
        
        browser?.browseResultsChangedHandler = { [weak self] results, changes in
            DispatchQueue.main.async {
                var devices: [DiscoveredDevice] = []
                for result in results {
                    if case .service(let name, let type, let domain, _) = result.endpoint {
                        devices.append(DiscoveredDevice(
                            name: name,
                            endpoint: result.endpoint,
                            type: type,
                            domain: domain
                        ))
                    }
                }
                self?.discoveredDevices = devices
            }
        }
        
        browser?.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    self?.streamingStatus = "Discovering devices..."
                case .failed(let error):
                    self?.streamingStatus = "Discovery failed: \(error)"
                default:
                    break
                }
            }
        }
        
        browser?.start(queue: queue)
    }
    
    func stopDiscovery() {
        browser?.cancel()
        browser = nil
        discoveredDevices = []
        streamingStatus = "Discovery stopped"
    }
    
    func connectToDevice(_ device: DiscoveredDevice) {
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = false
        
        connection = NWConnection(to: device.endpoint, using: parameters)
        
        connection?.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    self?.isClientConnected = true
                    self?.connectionStatus = "Connected to \(device.name)"
                    self?.streamingStatus = "Receiving health data"
                    self?.startReceiveLiveActivity(deviceName: device.name)
                case .cancelled:
                    self?.isClientConnected = false
                    self?.connectionStatus = "Disconnected"
                    self?.streamingStatus = "Ready to connect"
                    self?.stopLiveActivity()
                case .failed(let error):
                    self?.connectionStatus = "Connection failed: \(error)"
                    self?.streamingStatus = "Connection failed"
                    self?.isClientConnected = false
                    self?.stopLiveActivity()
                default:
                    break
                }
            }
        }
        
        connection?.start(queue: queue)
        if let connection = connection {
            Task {
                await startReceivingData(on: connection)
            }
        }
    }
    
    func disconnect() {
        stopLiveActivity()
        connection?.cancel()
        connection = nil
        isClientConnected = false
        connectionStatus = "Disconnected"
    }
    
    // MARK: - Data Reception
    
    private func startReceivingData(on connection: NWConnection) async {
        await receiveMessage(on: connection)
    }
    
    private func receiveMessage(on connection: NWConnection) async {
        // First receive the 4-byte length header
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, _, error in
            guard let data = data, data.count == 4, error == nil else {
                if error != nil {
                    print("Error receiving length: \(error!)")
                }
                return
            }
            
            // Extract message length
            let length = data.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            
            // Now receive the actual message
            connection.receive(minimumIncompleteLength: Int(length), maximumLength: Int(length)) { messageData, _, _, messageError in
                guard let messageData = messageData, messageData.count == length, messageError == nil else {
                    if messageError != nil {
                        print("Error receiving message: \(messageError!)")
                    }
                    return
                }
                
                // Process the received data
                Task { @MainActor [weak self] in
                    self?.processReceivedData(messageData)
                }
                
                // Continue receiving next message
                Task { @MainActor [weak self] in
                    await self?.receiveMessage(on: connection)
                }
            }
        }
    }
    
    private func processReceivedData(_ data: Data) {
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let packet = try decoder.decode(HealthDataPacket.self, from: data)
            
            DispatchQueue.main.async {
                self.totalDataReceived += 1
                self.connectionStatus = "Receiving data (\(self.totalDataReceived) samples)"
                self.handleReceivedHealthData(packet)
            }
            
        } catch {
            print("Failed to decode received data: \(error)")
        }
    }
    
    private func handleReceivedHealthData(_ packet: HealthDataPacket) {
        print("📊 Received health data: HR=\(packet.heartRate ?? 0), HRV=\(packet.hrv ?? 0), Scenario=\(packet.scenario)")
        
        // Update UI immediately
        lastReceivedPacket = packet
        
        // Add to recent samples list (keep last 10)
        let sample = ReceivedSample(
            timestamp: packet.timestamp,
            heartRate: packet.heartRate,
            hrv: packet.hrv,
            scenario: packet.scenario,
            savedToHealthKit: false
        )
        
        recentSamples.insert(sample, at: 0)
        if recentSamples.count > 5 {
            recentSamples = Array(recentSamples.prefix(5))
        }
        
        // Save to HealthKit immediately
        Task {
            await saveReceivedDataToHealthKit(packet)
        }
    }
    
    private func saveReceivedDataToHealthKit(_ packet: HealthDataPacket) async {
        guard let healthStore = getHealthStore() else { return }
        
        do {
            var samples: [HKSample] = []
            
            // Save heart rate data
            if let hr = packet.heartRate,
               let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) {
                let hrQuantity = HKQuantity(unit: HKUnit.count().unitDivided(by: .minute()), doubleValue: hr)
                let hrSample = HKQuantitySample(
                    type: hrType,
                    quantity: hrQuantity,
                    start: packet.timestamp,
                    end: packet.timestamp,
                    metadata: [HKMetadataKeyExternalUUID: "\(packet.timestamp.timeIntervalSince1970)-hr"]
                )
                samples.append(hrSample)
            }
            
            // Save HRV data
            if let hrv = packet.hrv,
               let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) {
                let hrvQuantity = HKQuantity(unit: HKUnit.secondUnit(with: .milli), doubleValue: hrv)
                let hrvSample = HKQuantitySample(
                    type: hrvType,
                    quantity: hrvQuantity,
                    start: packet.timestamp,
                    end: packet.timestamp,
                    metadata: [HKMetadataKeyExternalUUID: "\(packet.timestamp.timeIntervalSince1970)-hrv"]
                )
                samples.append(hrvSample)
            }
            
            // Save to HealthKit
            if !samples.isEmpty {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    healthStore.save(samples) { success, error in
                        if let error = error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume()
                        }
                    }
                }
                print("✅ Saved \(samples.count) samples to HealthKit")
                
                // Update UI on main thread
                DispatchQueue.main.async {
                    self.healthKitSaveCount += samples.count
                    
                    // Update the corresponding sample in recentSamples
                    if let index = self.recentSamples.firstIndex(where: { 
                        abs($0.timestamp.timeIntervalSince(packet.timestamp)) < 1.0 
                    }) {
                        self.recentSamples[index].savedToHealthKit = true
                    }
                    
                    // Update Live Activity
                    self.updateLiveActivity()
                }
            }
            
        } catch {
            print("❌ Failed to save received data to HealthKit: \(error)")
            DispatchQueue.main.async {
                self.healthKitErrors.append("Failed to save: \(error.localizedDescription)")
                // Keep only last 5 errors
                if self.healthKitErrors.count > 5 {
                    self.healthKitErrors = Array(self.healthKitErrors.suffix(5))
                }
            }
        }
    }
    
    private func getHealthStore() -> HKHealthStore? {
        #if targetEnvironment(simulator)
        return HKHealthStore()
        #else
        return nil // Don't save on device to avoid conflicts
        #endif
    }
    
    func verifyHealthKitData() async -> HealthKitVerificationResult {
        guard let healthStore = getHealthStore() else {
            return HealthKitVerificationResult(
                totalHeartRateCount: 0,
                totalHRVCount: 0,
                recentHeartRateValues: [],
                recentHRVValues: [],
                lastUpdateTime: nil,
                error: "HealthKit not available"
            )
        }
        
        do {
            // Query recent heart rate data
            let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
            let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!
            
            let last24Hours = Date().addingTimeInterval(-24 * 60 * 60)
            let predicate = HKQuery.predicateForSamples(withStart: last24Hours, end: Date(), options: .strictStartDate)
            
            // Count total samples
            let hrCount = try await queryCount(for: hrType, predicate: predicate, healthStore: healthStore)
            let hrvCount = try await queryCount(for: hrvType, predicate: predicate, healthStore: healthStore)
            
            // Get recent values
            let recentHR = try await queryRecentValues(for: hrType, predicate: predicate, healthStore: healthStore, unit: HKUnit.count().unitDivided(by: .minute()))
            let recentHRV = try await queryRecentValues(for: hrvType, predicate: predicate, healthStore: healthStore, unit: HKUnit.secondUnit(with: .milli))
            
            return HealthKitVerificationResult(
                totalHeartRateCount: hrCount,
                totalHRVCount: hrvCount,
                recentHeartRateValues: recentHR,
                recentHRVValues: recentHRV,
                lastUpdateTime: Date(),
                error: nil
            )
            
        } catch {
            return HealthKitVerificationResult(
                totalHeartRateCount: 0,
                totalHRVCount: 0,
                recentHeartRateValues: [],
                recentHRVValues: [],
                lastUpdateTime: nil,
                error: error.localizedDescription
            )
        }
    }
    
    private func queryCount(for type: HKQuantityType, predicate: NSPredicate, healthStore: HKHealthStore) async throws -> Int {
        return try await withCheckedThrowingContinuation { continuation in
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sortDescriptor]) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    let count = samples?.count ?? 0
                    continuation.resume(returning: count)
                }
            }
            healthStore.execute(query)
        }
    }
    
    private func queryRecentValues(for type: HKQuantityType, predicate: NSPredicate, healthStore: HKHealthStore, unit: HKUnit) async throws -> [Double] {
        return try await withCheckedThrowingContinuation { continuation in
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 5, sortDescriptors: [sortDescriptor]) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    let values = (samples as? [HKQuantitySample])?.map { sample in
                        sample.quantity.doubleValue(for: unit)
                    } ?? []
                    continuation.resume(returning: values)
                }
            }
            healthStore.execute(query)
        }
    }
    
    // MARK: - Live Activity Management
    
    private func startBroadcastLiveActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        
        // Generate shared flight number if not already set
        if sharedFlightNumber == nil {
            sharedFlightNumber = "HK\(Int.random(in: 100...999))"
        }
        
        let attributes = NetworkStreamActivityAttributes(
            startTime: Date(),
            mode: "broadcast"
        )
        
        let initialState = NetworkStreamActivityAttributes.ContentState(
            isConnected: true,
            connectionType: "BROADCASTING",
            deviceName: UIDevice.current.name,
            totalSamples: totalDataSent,
            samplesPerMinute: 0,
            lastSampleTime: nil,
            lastHeartRate: nil,
            lastHRV: nil,
            lastScenario: nil,
            status: "BOARDING",
            healthKitSaves: 0,
            lastUpdateTime: Date(),
            flightNumber: sharedFlightNumber!,
            gate: "B\(Int.random(in: 1...30))",
            destination: "SIMULATOR"
        )
        
        do {
            currentActivity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: initialState, staleDate: nil)
            )
            print("🚀 Started broadcast Live Activity")
            
            // Update to "IN FLIGHT" after a brief delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.updateLiveActivityStatus("IN FLIGHT")
            }
        } catch {
            print("❌ Failed to start broadcast Live Activity: \(error)")
        }
    }
    
    private func startReceiveLiveActivity(deviceName: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        
        // Use same flight number as broadcaster if available
        if sharedFlightNumber == nil {
            sharedFlightNumber = "HK\(Int.random(in: 100...999))"
        }
        
        let attributes = NetworkStreamActivityAttributes(
            startTime: Date(),
            mode: "receive"
        )
        
        let initialState = NetworkStreamActivityAttributes.ContentState(
            isConnected: true,
            connectionType: "RECEIVING",
            deviceName: deviceName.uppercased(),
            totalSamples: totalDataReceived,
            samplesPerMinute: 0,
            lastSampleTime: nil,
            lastHeartRate: nil,
            lastHRV: nil,
            lastScenario: nil,
            status: "BOARDING",
            healthKitSaves: healthKitSaveCount,
            lastUpdateTime: Date(),
            flightNumber: sharedFlightNumber!,
            gate: "A\(Int.random(in: 1...30))",
            destination: "HEALTHKIT"
        )
        
        do {
            currentActivity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: initialState, staleDate: nil)
            )
            print("📱 Started receive Live Activity")
            
            // Update to "IN FLIGHT" after a brief delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.updateLiveActivityStatus("IN FLIGHT")
            }
        } catch {
            print("❌ Failed to start receive Live Activity: \(error)")
        }
    }
    
    private func updateLiveActivity() {
        guard let activity = currentActivity else { return }
        
        let samplesPerMin = calculateSamplesPerMinute()
        let isBroadcast = activity.attributes.mode == "broadcast"
        
        // Use appropriate data source based on mode
        let relevantPacket = isBroadcast ? lastSentPacket : lastReceivedPacket
        
        let updatedState = NetworkStreamActivityAttributes.ContentState(
            isConnected: isClientConnected,
            connectionType: isBroadcast ? "BROADCASTING" : "RECEIVING",
            deviceName: activity.content.state.deviceName ?? "UNKNOWN",
            totalSamples: isBroadcast ? totalDataSent : totalDataReceived,
            samplesPerMinute: samplesPerMin,
            lastSampleTime: relevantPacket?.timestamp,
            lastHeartRate: relevantPacket?.heartRate,
            lastHRV: relevantPacket?.hrv,
            lastScenario: relevantPacket?.scenario.uppercased(),
            status: isClientConnected ? "IN FLIGHT" : "DELAYED",
            healthKitSaves: healthKitSaveCount,
            lastUpdateTime: Date(),
            flightNumber: activity.content.state.flightNumber,
            gate: activity.content.state.gate,
            destination: activity.content.state.destination.uppercased()
        )
        
        Task {
            await activity.update(ActivityContent(state: updatedState, staleDate: nil))
        }
    }
    
    private func updateLiveActivityStatus(_ status: String) {
        guard let activity = currentActivity else { return }
        
        let updatedState = NetworkStreamActivityAttributes.ContentState(
            isConnected: activity.content.state.isConnected,
            connectionType: activity.content.state.connectionType,
            deviceName: activity.content.state.deviceName ?? "Unknown",
            totalSamples: activity.content.state.totalSamples,
            samplesPerMinute: activity.content.state.samplesPerMinute,
            lastSampleTime: activity.content.state.lastSampleTime,
            lastHeartRate: activity.content.state.lastHeartRate,
            lastHRV: activity.content.state.lastHRV,
            lastScenario: activity.content.state.lastScenario,
            status: status,
            healthKitSaves: activity.content.state.healthKitSaves,
            lastUpdateTime: Date(),
            flightNumber: activity.content.state.flightNumber,
            gate: activity.content.state.gate,
            destination: activity.content.state.destination
        )
        
        Task {
            await activity.update(ActivityContent(state: updatedState, staleDate: nil))
        }
    }
    
    private func stopLiveActivity() {
        guard let activity = currentActivity else { return }
        
        let finalState = NetworkStreamActivityAttributes.ContentState(
            isConnected: false,
            connectionType: activity.content.state.connectionType,
            deviceName: activity.content.state.deviceName ?? "Unknown",
            totalSamples: activity.content.state.totalSamples,
            samplesPerMinute: 0,
            lastSampleTime: activity.content.state.lastSampleTime,
            lastHeartRate: activity.content.state.lastHeartRate,
            lastHRV: activity.content.state.lastHRV,
            lastScenario: activity.content.state.lastScenario,
            status: "ARRIVED",
            healthKitSaves: activity.content.state.healthKitSaves,
            lastUpdateTime: Date(),
            flightNumber: activity.content.state.flightNumber,
            gate: activity.content.state.gate,
            destination: activity.content.state.destination
        )
        
        Task {
            await activity.end(ActivityContent(state: finalState, staleDate: nil), dismissalPolicy: .after(Date().addingTimeInterval(5)))
            print("✅ Ended Live Activity")
        }
        
        currentActivity = nil
    }
    
    private func calculateSamplesPerMinute() -> Double {
        let now = Date()
        let oneMinuteAgo = now.addingTimeInterval(-60)
        let recentSampleCount = recentSamples.filter { $0.timestamp > oneMinuteAgo }.count
        return Double(recentSampleCount)
    }
}

// MARK: - Supporting Types

struct DiscoveredDevice: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let endpoint: NWEndpoint
    let type: String
    let domain: String?
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(type)
    }
    
    static func ==(lhs: DiscoveredDevice, rhs: DiscoveredDevice) -> Bool {
        lhs.name == rhs.name && lhs.type == rhs.type
    }
}

struct HealthDataPacket: Codable {
    let timestamp: Date
    let heartRate: Double?
    let hrv: Double?
    let scenario: String
    let source: String
    
    init(timestamp: Date = Date(), heartRate: Double? = nil, hrv: Double? = nil, scenario: String, source: String = "RealTimeStream") {
        self.timestamp = timestamp
        self.heartRate = heartRate
        self.hrv = hrv
        self.scenario = scenario
        self.source = source
    }
}

struct ReceivedSample: Identifiable, Hashable {
    let id = UUID()
    let timestamp: Date
    let heartRate: Double?
    let hrv: Double?
    let scenario: String
    var savedToHealthKit: Bool
}

struct HealthKitVerificationResult {
    let totalHeartRateCount: Int
    let totalHRVCount: Int
    let recentHeartRateValues: [Double]
    let recentHRVValues: [Double]
    let lastUpdateTime: Date?
    let error: String?
}
