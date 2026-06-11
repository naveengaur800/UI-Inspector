//
//  Annotation.swift
//  DesignReviewKit
//
//  Created by Naveen Gaur on 11/06/2026.
//

import CoreGraphics
import Foundation

/// User-drawn rectangle with its commentary.
nonisolated struct Annotation: Identifiable, Sendable {
    let id: UUID

    /// Rect in unit coordinates (0…1) relative to the captured screenshot.
    /// One normalized source of truth drives the canvas, review thumbnails, and PDF.
    var normalizedRect: CGRect

    var severity: Severity

    /// Commentary text. Non-empty by construction — an annotation only exists once its comment is saved.
    var comment: String

    /// Creation time; orders annotations into session-wide issue numbers.
    let createdAt: Date

    /// Convert the normalized rect into a concrete coordinate space (image points, view points, or PDF points).
    func rect(in size: CGSize) -> CGRect {
        normalizedRect.denormalized(in: CGRect(origin: .zero, size: size))
    }
}
