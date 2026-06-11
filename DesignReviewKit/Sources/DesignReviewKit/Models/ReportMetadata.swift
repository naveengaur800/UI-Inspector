//
//  ReportMetadata.swift
//  DesignReviewKit
//
//  Created by Naveen Gaur on 11/06/2026.
//

import UIKit

/// Host app identity captured at session start, shown on the report cover.
nonisolated struct AppMetadata: Sendable {
    let name: String
    let version: String
    let build: String

    /// Read the host app's identity from its bundle.
    static func current(bundle: Bundle = .main) -> AppMetadata {
        let info = bundle.infoDictionary ?? [:]
        let displayName = info["CFBundleDisplayName"] as? String
        let bundleName = info["CFBundleName"] as? String
        return AppMetadata(
            name: displayName ?? bundleName ?? "Unknown App",
            version: info["CFBundleShortVersionString"] as? String ?? "?",
            build: info["CFBundleVersion"] as? String ?? "?"
        )
    }
}

/// Device context captured at session start — layout feedback depends on it.
nonisolated struct DeviceMetadata: Sendable {
    let model: String
    let system: String
    let screenPointSize: CGSize
    let displayScale: CGFloat

    /// Read device context from the window the session was started in.
    static func current(for window: UIWindow) -> DeviceMetadata {
        let device = UIDevice.current
        return DeviceMetadata(
            model: device.model,
            system: "\(device.systemName) \(device.systemVersion)",
            screenPointSize: window.bounds.size,
            displayScale: window.traitCollection.displayScale
        )
    }
}
