//
//  BluetoothManager.swift
//  Limit
//
//  Created by STDG (Sebastian Dengler) on 22.02.26.
//

import Foundation
import CoreBluetooth
import Combine

class BluetoothManager: NSObject, ObservableObject {
    @Published var isScanning = false
    @Published var isConnected = false
    @Published var discoveredScale: CBPeripheral?
    @Published var currentForce: Double = 0.0
    @Published var connectionStatus = "Disconnected"

    private var centralManager: CBCentralManager!
    private var printCounter = 0

    // IF_B7 scale name
    private let targetScaleName = "IF_B7"

    // DisplayLink for throttled UI updates (prevents main thread overload)
    private var displayLink: DisplayLink?
    private var pendingForceValue: Double = 0.0
    private let forceLock = NSLock()

    // Background queue for BLE operations (prevents blocking main thread)
    private let bleQueue = DispatchQueue(label: "com.limit.bluetooth", qos: .userInitiated)

    // Scan restart timer to prevent iOS throttling (restarts scan every 10s)
    private var scanRestartTimer: Timer?

    override init() {
        super.init()
        // Use background queue for BLE callbacks to avoid blocking main thread
        centralManager = CBCentralManager(delegate: self, queue: bleQueue)
    }
    
    func startScanning() {
        guard centralManager.state == .poweredOn else {
            connectionStatus = "Bluetooth not available"
            return
        }

        isScanning = true
        isConnected = false
        connectionStatus = "Scanning for IF_B7 scale..."

        // Start DisplayLink for throttled force updates (60Hz max)
        startDisplayLink()

        // Start scan restart timer to prevent iOS throttling
        startScanRestartTimer()

        // Scan for ALL peripherals, allow duplicates to get continuous updates
        centralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }

    func stopScanning() {
        centralManager.stopScan()
        isScanning = false
        isConnected = false
        connectionStatus = "Stopped scanning"
        currentForce = 0.0

        // Stop DisplayLink
        stopDisplayLink()

        // Stop scan restart timer
        stopScanRestartTimer()
    }
    
    func disconnect() {
        stopScanning()
    }

    // MARK: - DisplayLink Management (Performance Optimization)

    private func startDisplayLink() {
        displayLink = DisplayLink()
        displayLink?.start { [weak self] in
            self?.flushForceUpdate()
        }
    }

    private func stopDisplayLink() {
        displayLink?.stop()
        displayLink = nil
    }

    private func flushForceUpdate() {
        // Update published force value at screen refresh rate (60Hz)
        forceLock.lock()
        let latestForce = pendingForceValue
        forceLock.unlock()

        // Update on main thread (required for @Published)
        DispatchQueue.main.async {
            self.currentForce = latestForce
        }
    }

    // MARK: - Scan Restart Timer (Prevents iOS Throttling)

    private func startScanRestartTimer() {
        // Restart scan every 10 seconds to prevent iOS from throttling duplicate advertisements
        scanRestartTimer?.invalidate()
        scanRestartTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.restartScan()
        }
    }

    private func stopScanRestartTimer() {
        scanRestartTimer?.invalidate()
        scanRestartTimer = nil
    }

    private func restartScan() {
        guard isScanning, centralManager.state == .poweredOn else { return }

        // Briefly stop and restart scan to reset iOS throttling
        centralManager.stopScan()
        centralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])

        print("🔄 Restarted BLE scan to prevent throttling")
    }

    private func parseManufacturerData(_ data: Data) -> Double? {
        let bytes = [UInt8](data)
        
        // Only print every 20th packet to reduce spam
        printCounter += 1
        let shouldPrint = printCounter % 20 == 0
        
        if shouldPrint {
            print("📊 Raw bytes: \(bytes.map { String(format: "%02X", $0) }.joined(separator: " "))")
        }
        
        guard data.count >= 14 else {
            if shouldPrint {
                print("⚠️ Manufacturer data too short")
            }
            return nil
        }
        
        // Weight is at bytes 12-13 (0-indexed)
        // Format: 16-bit BIG-ENDIAN value in units of 10 grams (0.01 kg)
        // Example: bytes [03 E8] = 0x03E8 = 1000 decimal = 10.00 kg
        // Example: bytes [01 5E] = 0x015E = 350 decimal = 3.50 kg
        
        let rawValue = UInt16(bytes[13]) | (UInt16(bytes[12]) << 8)  // Big-endian
        let weightKg = Double(rawValue) / 100.0  // Convert to kg (units of 0.01 kg)
        
        if shouldPrint {
            print("📊 Weight: \(String(format: "%.2f", weightKg)) kg (raw: 0x\(String(format: "%04X", rawValue)) = \(rawValue))")
        }
        
        return weightKg
    }
}

// MARK: - CBCentralManagerDelegate
extension BluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let status: String
        let logMessage: String

        switch central.state {
        case .poweredOn:
            status = "Ready to scan"
            logMessage = "✅ Bluetooth is powered on"
        case .poweredOff:
            status = "Bluetooth is off"
            logMessage = "❌ Bluetooth is off"
        case .unauthorized:
            status = "Bluetooth not authorized"
            logMessage = "❌ Bluetooth not authorized"
        case .unsupported:
            status = "Bluetooth not supported"
            logMessage = "❌ Bluetooth not supported"
        default:
            status = "Bluetooth unavailable"
            logMessage = "⚠️ Bluetooth state: \(central.state.rawValue)"
        }

        // Update @Published property on main thread
        DispatchQueue.main.async {
            self.connectionStatus = status
        }
        print(logMessage)
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {

        guard let name = peripheral.name, name == targetScaleName else { return }

        // Mark as "connected" (we're receiving data) - update on main thread
        if !isConnected {
            DispatchQueue.main.async {
                self.isConnected = true
                self.discoveredScale = peripheral
                self.connectionStatus = "Receiving data from IF_B7"
            }
            print("✅ Found IF_B7 scale - reading broadcast data")
        }

        // Extract manufacturer data and buffer it (DisplayLink will flush at 60Hz)
        if let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data {
            if let weight = parseManufacturerData(manufacturerData) {
                // Buffer force value (no immediate main thread dispatch)
                forceLock.lock()
                pendingForceValue = weight
                forceLock.unlock()
            }
        }
    }
}
