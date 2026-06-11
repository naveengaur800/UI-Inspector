//
//  CapturedScreen.swift
//  DesignReviewKit
//
//  Created by Naveen Gaur on 11/06/2026.
//

import UIKit

/// One frozen screenshot of the host app plus the annotations drawn on it.
nonisolated struct CapturedScreen: Identifiable, Sendable {
    let id: UUID

    /// JPEG-compressed capture; decode on demand to keep multi-screen sessions memory-bounded.
    let imageData: Data

    /// Capture size in points; pairs with normalized annotation rects for any target space.
    let imagePointSize: CGSize

    /// Display scale at capture time; restore it on decode so point sizes stay true.
    let displayScale: CGFloat

    let capturedAt: Date

    var annotations: [Annotation]

    /// Frames of the window's views and accessibility elements at capture time,
    /// in unit coordinates. Measurement mode snaps to these edges.
    let elementFrames: [CGRect]

    /// Decode the stored capture at its original scale.
    func makeImage() -> UIImage? {
        UIImage(data: imageData, scale: displayScale)
    }

}
