//
//  DisplayLink.swift
//  Limit
//
//  DisplayLink wrapper for synchronizing UI updates with screen refresh rate
//  Inspired by Crane project - prevents excessive chart redraws
//

import Foundation
import QuartzCore

/// Wraps CADisplayLink to synchronize updates with screen refresh rate
/// Prevents excessive UI updates by capping at 60Hz instead of processing every BLE packet
class DisplayLink {
    private var displayLink: CADisplayLink?
    private var callback: (() -> Void)?

    /// Start the display link with a callback that fires on each frame
    func start(callback: @escaping () -> Void) {
        self.callback = callback

        // Create display link
        displayLink = CADisplayLink(target: self, selector: #selector(frame))
        displayLink?.add(to: .main, forMode: .common)
    }

    /// Stop the display link
    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        callback = nil
    }

    @objc private func frame() {
        callback?()
    }

    deinit {
        stop()
    }
}
