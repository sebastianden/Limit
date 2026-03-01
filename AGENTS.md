# AGENTS.md - Developer & AI Agent Guide

## Project Overview

**Limit** is an iOS app for climbing finger strength training that connects to a Bluetooth scale (IF_B7) and implements the Kellawan & Tschakovsky Critical Force test protocol.

### Core Features
- **Max Force Test**: Simple maximum force measurement
- **Critical Force Test**: 24-phase protocol (7s work, 3s rest) measuring CF and W' (work capacity above CF)
- **Hand & Bodyweight Tracking**: Pre-test configuration captures which hand (left/right) and current bodyweight
- **Data Visualization**: Real-time charts + complete test visualization with CF reference line
- **Progress Tracking**: Historical charts showing CF and W' trends over time by hand, with absolute and bodyweight-relative views
- **History & Export**: Save results with full raw data, export to CSV with relative percentages

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
├── BluetoothManager.swift          # BLE communication + performance optimizations
├── CriticalForceTestView.swift     # CF test UI
├── CriticalForceViewModel.swift    # CF test logic + calculations
├── ForceTestViewModel.swift        # Max force test logic
├── TestConfigurationView.swift     # Pre-test hand/bodyweight input
├── TestResult.swift                # Data models + CSV export
├── PersistenceManager.swift        # Save/load (JSON)
├── HistoryView.swift               # Test history UI + progress charts
└── Utils/
    └── DisplayLink.swift           # CADisplayLink wrapper for 60Hz UI sync
```

## Bluetooth Scale (IF_B7)

**Connection**: Passive BLE scanning - continuously reads from manufacturer data, no active pairing.

```swift
// Weight extraction from manufacturer data (bytes 12-13)
let rawValue = UInt16(bytes[13]) | (UInt16(bytes[12]) << 8)  // Big-endian
let weightKg = Double(rawValue) / 100.0  // 0.01 kg units
```

### Performance Optimizations

The app implements multiple performance optimizations to maintain consistent ~10Hz BLE readings throughout long test sessions:

1. **DisplayLink Synchronization** (60Hz cap)
   - UI updates capped at screen refresh rate (60Hz) instead of processing every BLE packet
   - Prevents SwiftUI from recalculating views thousands of times during 4-minute tests
   - Implemented in: `BluetoothManager`, `CriticalForceViewModel`, `ForceTestViewModel`

2. **Background Queue for BLE**
   - BLE callbacks run on dedicated background queue (not main thread)
   - Prevents main thread blocking from BLE operations
   - Queue: `DispatchQueue(label: "com.limit.bluetooth", qos: .userInitiated)`

3. **Buffered Force Updates**
   - BLE readings buffered in thread-safe storage (NSLock protected)
   - Flushed to `@Published` properties at 60Hz via DisplayLink
   - Reduces main thread DispatchQueue.async calls from ~10/sec to 60/sec max

4. **iOS BLE Scan Throttling Prevention**
   - iOS automatically throttles duplicate BLE advertisements after ~100 seconds
   - **Solution**: Automatic scan restart every 10 seconds
   - Briefly stops and restarts `scanForPeripherals()` to reset throttling
   - Timer managed with scan lifecycle (starts/stops with scanning)

5. **Batched Array Operations**
   - Data point trimming only every 100 readings (not on every update)
   - Converts O(n) cleanup operations from high frequency to low frequency
   - Keeps last 60 seconds of data for memory management

6. **Incremental Calculations**
   - Running sum for O(1) mean force calculation (not O(n) array reduce)
   - Incremental peak tracking (only compare latest value, not full scan)
   - Reuse calculated values instead of rescanning arrays

**Result**: Consistent ~10Hz BLE readings throughout entire test duration with smooth, responsive UI.

```swift
// DisplayLink pattern (used in BluetoothManager, ViewModels)
private var displayLink: DisplayLink?
private var pendingDataPoints: [DataPoint] = []
private let dataLock = NSLock()

// Buffer data on BLE callback (background queue)
dataLock.lock()
pendingDataPoints.append(newData)
dataLock.unlock()

// Flush at 60Hz (DisplayLink callback)
private func flushData() {
    dataLock.lock()
    defer { dataLock.unlock() }
    publishedData.append(contentsOf: pendingDataPoints)
    pendingDataPoints.removeAll()
}
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

## Pre-Test Configuration

Before each CF test, users are prompted to enter:
- **Hand**: Left or Right (segmented picker with L/R square icons)
- **Bodyweight**: Current bodyweight in kg (decimal input, validated 20-300 kg range)

Both fields are **required**. Configuration is presented as a sheet modal ([TestConfigurationView.swift](Limit/TestConfigurationView.swift)) when user taps "Start Test".

```swift
// Hand enum with icons
enum Hand: String, Codable, CaseIterable {
    case left = "Left"
    case right = "Right"

    var icon: String {
        switch self {
        case .left: return "l.square.fill"
        case .right: return "r.square.fill"
        }
    }
}
```

**Stored with test results** to enable:
- Hand-specific progress tracking
- Bodyweight-normalized comparisons (CF%, W'%)
- Historical trend analysis by hand

## Data Models

```swift
struct TestResult: Codable, Identifiable {
    let id: UUID
    let date: Date
    let criticalForce: Double
    let wPrime: Double
    let phases: [PhaseData]
    let hand: Hand?              // Left or Right
    let bodyweight: Double?      // kg (optional for backward compatibility)
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
  1. **Header**: Date, Hand, Bodyweight, CF, W', CF%, W'% (percentages if bodyweight available)
  2. **Phase Summary**: Phase-level metrics (peak force, mean force, impulse, duration)
  3. **Raw Force Data**: All individual readings (~10Hz)
- **Sharing**: UIActivityViewController with `ExportItem` wrapper for reliable presentation

**Example CSV Header**:
```
Critical Force Test Results
Date: Feb 28, 2026 at 1:30 PM
Hand: Right
Bodyweight: 75.5 kg
Critical Force (CF): 45.20 kg
W' (W-Prime): 234.5 kg·s
CF/kg: 59.9%
W'/kg: 310.6%
```

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
- Hand and bodyweight badges (L/R icons, figure icon)
- Relative values shown when bodyweight available (e.g., "59.9% of bodyweight")
- Complete test chart with CF line
- Phase-by-phase breakdown
- Export button

## Progress Tracking

**Location**: Top of History view (above test results list)

**Features**:
- **Line chart** with point markers showing historical trends
- **Three toggle controls**:
  1. **Metric**: Critical Force ↔ W'
  2. **View**: Absolute (kg/kg·s) ↔ Per kg BW (%)
  3. **Hand Filter**: All ↔ Left Only ↔ Right Only
- **Color coding**: Blue (Left hand), Green (Right hand)
- **Legend**: Always visible below chart

**Chart Behavior**:
- Shows all tests sorted chronologically (oldest → newest)
- Filters out tests without bodyweight when viewing relative percentages
- Separate trend lines for each hand when "All" filter selected
- Y-axis units adapt to selected metric and view (e.g., "60%", "45 kg")
- X-axis shows dates (Month/Day format)

**Implementation**: Swift Charts framework with LineMark + PointMark

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

**Last Updated**: 2026-03-01

**Status**: Feature complete with hand/bodyweight tracking, progress analytics, and comprehensive performance optimizations. Pre-test configuration captures hand (L/R) and bodyweight. CSV export includes relative percentages (CF%, W'%). Progress chart in History view shows trends over time with hand filtering and bodyweight normalization. Screen stays awake during tests. Performance optimizations include DisplayLink synchronization (60Hz UI cap), background BLE queue, buffered updates, automatic scan restart (10s interval) to prevent iOS throttling, batched array operations, and incremental calculations. Maintains consistent ~10Hz BLE readings throughout 4+ minute tests. Backward compatible with existing test data.
