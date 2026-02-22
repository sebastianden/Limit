# AGENTS.md - Developer & AI Agent Guide

## Project Overview

**Limit** is an iOS app for climbing finger strength training that connects to a Bluetooth scale (IF_B7) and implements scientific finger strength testing protocols.

### Core Features
- **Max Force Test**: Simple maximum force measurement
- **Critical Force (CF) Test**: Scientific protocol based on Kellawan & Tschakovsky methodology for measuring finger flexor critical force and W' (work capacity above CF)

## Architecture

### Tech Stack
- **Platform**: iOS (SwiftUI)
- **Language**: Swift
- **Bluetooth**: CoreBluetooth (passive scanning, no active connection)
- **State Management**: Combine framework with @Published properties

### Key Files

```
Limit/
├── LimitApp.swift                  # App entry point
├── ContentView.swift               # Main tab navigation + connection UI
├── BluetoothManager.swift          # Bluetooth scale communication
├── MaxForceTestView.swift          # Max force test UI
├── ForceTestViewModel.swift        # Max force test logic
├── CriticalForceTestView.swift     # CF test UI
└── CriticalForceViewModel.swift    # CF test logic + calculations
```

## Bluetooth Scale Integration

### IF_B7 Scale Details
- **Connection Type**: Passive BLE scanning (no active pairing required)
- **Scale Name**: "IF_B7"
- **Data Location**: Manufacturer data, bytes 12-13
- **Data Format**: 16-bit big-endian value in units of 0.01 kg
- **Update Rate**: Continuous broadcasts

### Implementation Notes
```swift
// Weight extraction from manufacturer data
let rawValue = UInt16(bytes[13]) | (UInt16(bytes[12]) << 8)  // Big-endian
let weightKg = Double(rawValue) / 100.0  // Convert to kg
```

**Important**: The app doesn't establish a traditional BLE connection. It continuously scans for advertisements and extracts force data from the manufacturer data field. This is why `disconnect()` just stops scanning.

## Critical Force Test - Scientific Background

### Protocol (from Research Paper)
- **Duration**: 24 phases (4 minutes) - shortened from original 30 phases (5 minutes)
- **Note**: Each "phase" = one work cycle (7s work + 3s rest)
- **Work Phase**: 7 seconds of maximum force application
- **Rest Phase**: 3 seconds with hands in anatomical position (no shaking allowed)
- **Preparation**: 10 seconds to get into position before test starts

### Key Metrics
1. **Current Force**: Real-time force reading from scale
2. **Critical Force (CF)**: Live-updating after each phase (calculated from last 6 phases with 1 SD outlier filtering)
3. **Mean Force**: Average force during each phase
4. **Peak Force**: Maximum force during each phase (used internally, not displayed)
5. **Impulse**: Force-time integral (kg·s) calculated using trapezoidal rule
6. **W' (W-Prime)**: Total impulse above CF threshold (calculated at test completion)

### Calculation Details

**Critical Force** (updated live after each phase when 6+ phases complete):
```swift
// 1. Get last 6 phases
let lastSix = Array(contractions.suffix(6))

// 2. Calculate mean and standard deviation
let mean = meanForces.reduce(0, +) / Double(meanForces.count)
let variance = meanForces.map { pow($0 - mean, 2) }.reduce(0, +) / count
let stdDev = sqrt(variance)

// 3. Filter outliers (1 SD cutoff)
let filteredForces = meanForces.filter { abs($0 - mean) <= stdDev }

// 4. CF = mean of filtered forces
criticalForce = filteredForces.reduce(0, +) / Double(filteredForces.count)

// This is called in saveContractionData() to update currentCriticalForce
```

**W' Calculation**:
```swift
// For each contraction: impulse above CF
let duration = contraction.endTime - contraction.startTime
let impulseAboveCF = max(0, (contraction.meanForce - CF) * duration)
wPrime = sum of all impulseAboveCF
```

## Test State Management

### Phase Transitions (CF Test)
```
PREPARATION (10s, blue)
    ↓ (beep + haptic)
WORK (7s, green) → saves phase data, updates CF (if ≥6 phases)
    ↓ (beep + haptic)
REST (3s, orange)
    ↓ (beep + haptic, increment counter)
WORK (7s, green) → repeat 24 times total
    ↓ (after 24th phase)
TEST COMPLETE → show results
```

### Important Implementation Detail
**Data collection only happens during WORK and REST phases**, not during PREPARATION. The chart starts at 0 seconds when the first work phase begins.

## UI Design Patterns

### Consistency Between Tests
Both Max Force and CF tests share:
- **Spacing**: 16pt between major sections
- **Metric Cards**: 42pt font for values, .headline for labels
- **Chart Height**: 170-200pt
- **Button Size**: `.controlSize(.large)` with 16pt spacing
- **Corner Radius**: 12pt on cards
- **Shadows**: `radius: 2` on cards

### CF Test Specific Considerations
- **ScrollView**: Wraps entire content to prevent overflow on smaller screens
- **Phase Indicator**: Fixed-width badge (95pt) to prevent layout shift between WORK/REST
- **Progress Bar**: Only shown during active test, displays "X / 24 phases"
- **Critical Force Metric**: Appears after 6th phase completes, updates live after each subsequent phase
  - Shown alongside Current Force in metric cards
  - Always visible once calculable (not phase-dependent like old Peak metric)

## Audio & Haptic Feedback

```swift
// Phase transitions trigger:
1. System beep sound (AudioServicesPlaySystemSound)
2. Haptic feedback via callback to view
3. Color change in UI (blue → green → orange)
```

## Common Pitfalls & Solutions

### 1. Layout Shifting
**Problem**: UI elements move when text changes (e.g., WORK → REST)
**Solution**: Use fixed-width frames for dynamic content
```swift
Text(phaseLabel)
    .frame(width: 95)  // Fixed width prevents shift
```

### 2. Chart Data During Preparation
**Problem**: Should data be collected during the 10-second preparation?
**Solution**: No. Data collection starts when first WORK phase begins.

### 3. Live CF Updates
**Problem**: When should Critical Force update?
**Solution**: Calculate and update `currentCriticalForce` after each phase completes (in `saveContractionData()`). Requires minimum 6 phases. This gives users real-time feedback on their CF value.

### 4. Completion Detection
**Problem**: When to mark the test as complete?
**Solution**: After 24th phase's WORK phase completes (don't wait for REST after last phase)

### 5. Phase Timer
**Problem**: Timer needs to handle three different durations
**Solution**: Switch statement in `updatePhaseTimer()`:
```swift
let phaseDuration: TimeInterval
switch currentPhase {
case .preparation: phaseDuration = preparationDuration
case .work: phaseDuration = workDuration
case .rest: phaseDuration = restDuration
}
```

### 6. Memory Management
Keep only last 60 seconds of force data points to prevent memory growth during long sessions.

## Testing Considerations

### Manual Testing Checklist
- [ ] Bluetooth connection/disconnection works
- [ ] Phase transitions occur at correct intervals (10s/7s/3s)
- [ ] Audio beeps play on transitions
- [ ] Haptic feedback triggers
- [ ] Critical Force appears after 6th phase completes
- [ ] Critical Force updates after each subsequent phase
- [ ] Progress bar shows "X / 24 phases" correctly
- [ ] Test completes after 24 phases
- [ ] CF and W' calculations are correct
- [ ] Results screen shows all phase data
- [ ] Reset button clears all state (including currentCriticalForce)
- [ ] Chart displays last 10 seconds correctly
- [ ] No UI overlapping on smaller screens

### Edge Cases
1. **User stops test mid-way**: Should reset cleanly
2. **Bluetooth disconnects during test**: Test should stop gracefully
3. **Zero force readings**: Should handle gracefully (don't divide by zero)
4. **Very high forces**: UI should not break layout
5. **Fast tab switching**: State should persist per tab

## Future Enhancement Ideas

1. **Data Persistence**: Save test results to local database
2. **History View**: Track progress over time
3. **Customizable Protocols**: Allow users to adjust work/rest durations
4. **Export Results**: Share CSV or PDF reports
5. **Multiple Scales**: Support for other Bluetooth scale models
6. **Training Plans**: Structured workout programs
7. **Grip Types**: Support for different grip positions (half crimp, full crimp, open hand)
8. **Countdown Sounds**: Different beeps for 3-2-1 countdown

## References

- Scientific Paper: Kellawan & Tschakovsky methodology for finger flexor critical force determination
- Protocol: 7:3s work-to-rest ratio with rhythmic isometric maximum voluntary contractions
- Statistical Method: 1 SD cutoff for outlier removal in end-test force calculation

## Development Tips

### When Adding New Tests
1. Create separate ViewModel (inherit patterns from existing ones)
2. Create separate View (maintain UI consistency)
3. Add new tab in `ContentView.swift`
4. Reuse `BluetoothManager` - don't create separate instances
5. Maintain 16pt spacing and consistent styling

### When Modifying UI
- Always test on smallest supported iPhone screen
- Use ScrollView if content might overflow
- Maintain visual consistency between tabs
- Test with both light and dark mode

### When Debugging Bluetooth
- Check `BluetoothManager` print statements (every 20th packet)
- Verify manufacturer data byte parsing
- Confirm scale is broadcasting (check with LightBlue app)
- Remember: no active connection, just passive scanning

---

**Last Updated**: 2026-02-22
**Project Status**: Core functionality complete, ready for enhancements
