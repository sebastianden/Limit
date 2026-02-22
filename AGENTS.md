# AGENTS.md - Developer & AI Agent Guide

## Project Overview

**Limit** is an iOS app for climbing finger strength training that connects to a Bluetooth scale (IF_B7) and implements the Kellawan & Tschakovsky Critical Force test protocol.

### Core Features
- **Max Force Test**: Simple maximum force measurement
- **Critical Force Test**: 24-phase protocol (7s work, 3s rest) measuring CF and W' (work capacity above CF)
- **Data Visualization**: Real-time charts + complete test visualization with CF reference line
- **History & Export**: Save results with full raw data, export to CSV

## Architecture

### Tech Stack
- **Platform**: iOS (SwiftUI)
- **Bluetooth**: CoreBluetooth (passive scanning, no pairing)
- **State Management**: Combine framework
- **Persistence**: JSON (Documents directory)
- **Export**: Two-section CSV (summary + raw data)

### Navigation Structure
Flat TabView with 3 tabs (Max Force, Critical Force, History). No nested tabs to avoid overlapping tab bars.

### Key Files
```
Limit/
├── LimitApp.swift                  # App entry point
├── ContentView.swift               # Main tab navigation
├── BluetoothManager.swift          # BLE communication
├── CriticalForceTestView.swift     # CF test UI
├── CriticalForceViewModel.swift    # CF test logic + calculations
├── TestResult.swift                # Data models + CSV export
├── PersistenceManager.swift        # Save/load (JSON)
└── HistoryView.swift               # Test history UI
```

## Bluetooth Scale (IF_B7)

**Connection**: Passive BLE scanning - continuously reads from manufacturer data, no active pairing.

```swift
// Weight extraction from manufacturer data (bytes 12-13)
let rawValue = UInt16(bytes[13]) | (UInt16(bytes[12]) << 8)  // Big-endian
let weightKg = Double(rawValue) / 100.0  // 0.01 kg units
```

## Critical Force Test

### Protocol
- **Phases**: 24 work cycles (4 minutes total)
- **Preparation**: 10s to get in position
- **Work**: 7s maximum force
- **Rest**: 3s hands in anatomical position
- **Data Collection**: Only during WORK/REST, not preparation

### Phase Transitions
```
PREPARATION (10s, blue) → WORK (7s, green) → REST (3s, orange) → [repeat 24x] → COMPLETE
```

### Key Metrics & Calculations

**Critical Force (CF)** - Live-updating after 6+ phases:
```swift
// Uses last 6 phases with 1 SD outlier filtering
let lastSix = Array(contractions.suffix(6))
let mean = meanForces.reduce(0, +) / Double(meanForces.count)
let stdDev = sqrt(variance)
let filteredForces = meanForces.filter { abs($0 - mean) <= stdDev }
criticalForce = filteredForces.reduce(0, +) / Double(filteredForces.count)
```

**W' (W-Prime)**:
```swift
// Total impulse above CF
let impulseAboveCF = max(0, (contraction.meanForce - CF) * duration)
wPrime = sum of all impulseAboveCF
```

**Impulse** - Trapezoidal rule integration over work phase

## Data Models

```swift
struct TestResult: Codable, Identifiable {
    let id: UUID
    let date: Date
    let criticalForce: Double
    let wPrime: Double
    let phases: [PhaseData]
}

struct PhaseData: Codable, Identifiable {
    let id: UUID
    let phaseNumber: Int
    let peakForce: Double
    let meanForce: Double
    let impulse: Double
    let duration: Double
    let rawReadings: [RawForceReading]  // ~70 readings per 7s phase
}

struct RawForceReading: Codable {
    let timestamp: Double  // Relative to phase start
    let force: Double
}
```

## Data Persistence & Export

### Storage
- **Format**: JSON in Documents directory (`test_results.json`)
- **Encoding**: ISO8601 dates
- **Auto-save**: On test completion
- **Raw Data**: All force readings (~10Hz) stored with each phase

### CSV Export
- **Location**: `Caches/Exports/CF_Test_yyyy-MM-dd_HHmmss.csv`
- **Structure**:
  1. Summary statistics (phase-level metrics)
  2. Raw force data (all individual readings)
- **Sharing**: UIActivityViewController with `ExportItem` wrapper for reliable presentation

```swift
// Export pattern
struct ExportItem: Identifiable {
    let id = UUID()
    let url: URL
}

@State private var exportItem: ExportItem?

.sheet(item: $exportItem) { item in
    ShareSheet(items: [item.url])
}
```

## UI Components

### Test Visualization
- **Live Chart**: Last 10 seconds during test
- **Complete Chart**: Full test data with CF reference line (green dashed) in results and history views
- **Phase Indicator**: Fixed 95pt width to prevent layout shifts
- **Metric Cards**: 42pt values, consistent 16pt spacing, 12pt corner radius

### Results Display
- CF and W' cards with color coding (green/blue)
- Complete test chart with CF line
- Phase-by-phase breakdown
- Export button

## Common Pitfalls & Solutions

### 1. Layout Shifting
Use fixed-width frames for dynamic content:
```swift
Text(phaseLabel).frame(width: 95)  // Prevents WORK/REST shift
```

### 2. Data Collection Timing
Only collect data during WORK/REST phases, not preparation.

### 3. Live CF Updates
Update `currentCriticalForce` in `saveContractionData()` after each phase (min 6 phases required).

### 4. Test Completion
Complete after 24th WORK phase - don't wait for final REST.

### 5. Memory Management
Keep only last 60s of force data points during active tests.

### 6. Nested TabViews
Use flat 3-tab structure to avoid overlapping tab bars.

### 7. Export Sheet Presentation
Use `.sheet(item:)` with `Identifiable` wrapper, not `.sheet(isPresented:)` with conditional view.

### 8. File Sharing
Use cache directory (`Caches/Exports/`), not temp directory. Mark files as excluded from iCloud backup.

## iOS System Warnings

When exporting/sharing, iOS generates verbose console warnings (LaunchServices, CFPrefs, etc.). These are normal system logging from `UIActivityViewController` and can be safely ignored - they don't affect functionality.

---

**Last Updated**: 2026-02-22

**Status**: Core functionality complete. CSV export includes full raw data (work + rest phases). Test visualization with CF reference line in results and history views. Screen stays awake during tests.
