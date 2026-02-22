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
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    func startScanning() {
        guard centralManager.state == .poweredOn else {
            connectionStatus = "Bluetooth not available"
            return
        }
        
        isScanning = true
        isConnected = false
        connectionStatus = "Scanning for IF_B7 scale..."
        
        // Scan for ALL peripherals, allow duplicates to get continuous updates
        centralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }
    
    func stopScanning() {
        centralManager.stopScan()
        isScanning = false
        isConnected = false
        connectionStatus = "Stopped scanning"
        currentForce = 0.0
    }
    
    func disconnect() {
        stopScanning()
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
        switch central.state {
        case .poweredOn:
            connectionStatus = "Ready to scan"
            print("✅ Bluetooth is powered on")
        case .poweredOff:
            connectionStatus = "Bluetooth is off"
            print("❌ Bluetooth is off")
        case .unauthorized:
            connectionStatus = "Bluetooth not authorized"
            print("❌ Bluetooth not authorized")
        case .unsupported:
            connectionStatus = "Bluetooth not supported"
            print("❌ Bluetooth not supported")
        default:
            connectionStatus = "Bluetooth unavailable"
            print("⚠️ Bluetooth state: \(central.state.rawValue)")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        
        guard let name = peripheral.name, name == targetScaleName else { return }
        
        // Mark as "connected" (we're receiving data)
        if !isConnected {
            isConnected = true
            discoveredScale = peripheral
            connectionStatus = "Receiving data from IF_B7"
            print("✅ Found IF_B7 scale - reading broadcast data")
        }
        
        // Extract manufacturer data
        if let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data {
            if let weight = parseManufacturerData(manufacturerData) {
                DispatchQueue.main.async {
                    self.currentForce = weight
                }
            }
        }
    }
}
