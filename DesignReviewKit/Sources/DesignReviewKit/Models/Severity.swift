//
//  Severity.swift
//  DesignReviewKit
//
//  Created by Naveen Gaur on 11/06/2026.
//

import SwiftUI
import UIKit

/// Issue severity attached to every annotation's commentary.
nonisolated enum Severity: String, CaseIterable, Sendable {
    case low
    case medium
    case high

    /// Order severities appear in report summaries: most severe first.
    static let reportOrder: [Severity] = [.high, .medium, .low]

    /// Human-readable name shown in pickers, chips, and the PDF report.
    var displayName: String {
        switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }

    /// Tint used for annotation strokes, number badges, and severity chips.
    var uiColor: UIColor {
        switch self {
        case .low: .systemYellow
        case .medium: .systemOrange
        case .high: .systemRed
        }
    }

    /// SwiftUI counterpart of `uiColor`.
    var color: Color {
        Color(uiColor: uiColor)
    }
}
