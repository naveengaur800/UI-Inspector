//
//  CGRect+Normalization.swift
//  DesignReviewKit
//
//  Created by Naveen Gaur on 11/06/2026.
//

import CoreGraphics

/// Shared conversions between normalized (0…1) annotation space and concrete
/// coordinate spaces. The canvas, review thumbnails, and PDF all use these,
/// keeping one definition of how annotation geometry maps onto a frame.
nonisolated extension CGRect {

    /// Convert a rect in `frame`'s coordinate space into unit coordinates relative to `frame`.
    func normalized(in frame: CGRect) -> CGRect {
        guard frame.width > 0, frame.height > 0 else { return .zero }
        return CGRect(
            x: (origin.x - frame.origin.x) / frame.width,
            y: (origin.y - frame.origin.y) / frame.height,
            width: width / frame.width,
            height: height / frame.height
        )
    }

    /// Convert a unit-coordinate rect into `frame`'s coordinate space.
    func denormalized(in frame: CGRect) -> CGRect {
        CGRect(
            x: frame.origin.x + origin.x * frame.width,
            y: frame.origin.y + origin.y * frame.height,
            width: width * frame.width,
            height: height * frame.height
        )
    }

    /// Center a size within a container at the largest scale that fits.
    static func aspectFitRect(for size: CGSize, in container: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0, container.width > 0, container.height > 0 else {
            return container
        }
        let scale = min(container.width / size.width, container.height / size.height)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(
            x: container.minX + (container.width - fitted.width) / 2,
            y: container.minY + (container.height - fitted.height) / 2,
            width: fitted.width,
            height: fitted.height
        )
    }
}

nonisolated extension CGPoint {

    /// Clamp the point inside `rect` — keeps badges and drag locations within
    /// the rendered capture on both the canvas and the PDF.
    func clamped(to rect: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(x, rect.minX), rect.maxX),
            y: min(max(y, rect.minY), rect.maxY)
        )
    }
}
