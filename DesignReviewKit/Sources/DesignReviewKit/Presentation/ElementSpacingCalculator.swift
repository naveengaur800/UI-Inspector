//
//  ElementSpacingCalculator.swift
//  DesignReviewKit
//
//  Created by Naveen Gaur on 11/06/2026.
//

import CoreGraphics
import Foundation

/// One side's spacing readout: the span from the pressed element's edge to the
/// nearest thing in that direction, valued in capture points.
nonisolated struct SpacingMeasurement: Equatable {
    let start: CGPoint
    let end: CGPoint
    let points: CGFloat
}

/// The spacing readout for a long-pressed element: its outline and the measured
/// distances from each edge to the nearest neighbor or container edge.
nonisolated struct ElementSpacingReadout: Equatable {
    let elementRect: CGRect
    let measurements: [SpacingMeasurement]
}

/// Resolve a long-press into outward spacing over the captured element frames:
/// what a designer means by "how far is this from the things around it".
nonisolated enum ElementSpacingCalculator {

    /// Spacing thinner than this is touching, not a gap worth labeling.
    private static let minimumSpacingPoints: CGFloat = 2
    /// A neighbor must face the element across at least this much to count.
    private static let minimumFacingOverlap: CGFloat = 8
    /// A container counts as the pressed element's own shell (a button capsule
    /// around its label) only when every edge sits within this many points.
    private static let maximumSnugShellInset: CGFloat = 48

    /// Build the readout for the element under `location`.
    ///
    /// - Parameters:
    ///   - location: Press point in view coordinates.
    ///   - elementRects: Element frames in view coordinates.
    ///   - bounds: The full capture rect — the implicit outermost container, so
    ///     elements with nothing beside them measure to the screen edge.
    ///   - pointsPerViewUnit: Conversion from view distance to capture points.
    /// - Returns: The readout, or `nil` when nothing measurable is under the press.
    static func readout(
        at location: CGPoint,
        elementRects: [CGRect],
        bounds: CGRect,
        pointsPerViewUnit: CGFloat
    ) -> ElementSpacingReadout? {
        guard let element = pressedElement(at: location, among: elementRects, pointsPerViewUnit: pointsPerViewUnit) else {
            return nil
        }

        let measurements = spacingMeasurements(
            for: element,
            among: elementRects,
            bounds: bounds,
            pointsPerViewUnit: pointsPerViewUnit
        )
        guard !measurements.isEmpty else { return nil }
        return ElementSpacingReadout(elementRect: element, measurements: measurements)
    }

    /// The element the press means: the smallest rect under the finger, promoted
    /// to its snug shell when one exists — pressing a button's text targets the
    /// button capsule, while pressing a card's bare text stays on the text
    /// (the card is a container, not the element's own shell).
    private static func pressedElement(
        at location: CGPoint,
        among rects: [CGRect],
        pointsPerViewUnit: CGFloat
    ) -> CGRect? {
        let pressed = rects
            .filter { $0.contains(location) }
            .sorted { $0.width * $0.height < $1.width * $1.height }
        guard let smallest = pressed.first else { return nil }

        let maximumInset = maximumSnugShellInset / max(pointsPerViewUnit, 0.001)
        let snugShells = pressed.filter { shell in
            guard strictlyContains(shell, smallest) else { return false }
            return smallest.minX - shell.minX <= maximumInset
                && shell.maxX - smallest.maxX <= maximumInset
                && smallest.minY - shell.minY <= maximumInset
                && shell.maxY - smallest.maxY <= maximumInset
        }
        // The outermost snug shell is the element's visual boundary.
        return snugShells.max { $0.width * $0.height < $1.width * $1.height } ?? smallest
    }

    /// Whether `candidate` sits inside `container` and is meaningfully smaller —
    /// near-identical frames are duplicates of the same element, not content.
    private static func strictlyContains(_ container: CGRect, _ candidate: CGRect) -> Bool {
        guard container != candidate else { return false }
        let isMeaningfullySmaller = container.width - candidate.width > 0.5
            || container.height - candidate.height > 0.5
        return isMeaningfullySmaller && container.insetBy(dx: -0.25, dy: -0.25).contains(candidate)
    }

    // MARK: - Outward Measurement

    /// Measure each side's gap to the first edge in that direction: a facing
    /// neighbor's near edge, or the containing element's inner edge when
    /// nothing sits between.
    private static func spacingMeasurements(
        for element: CGRect,
        among rects: [CGRect],
        bounds: CGRect,
        pointsPerViewUnit: CGFloat
    ) -> [SpacingMeasurement] {
        var containers = rects.filter { strictlyContains($0, element) }
        if strictlyContains(bounds, element) {
            containers.append(bounds)
        }
        var measurements: [SpacingMeasurement] = []

        func appendIfMeaningful(distance: CGFloat?, from start: CGPoint, towards direction: CGVector) {
            guard let distance else { return }
            let points = distance * pointsPerViewUnit
            guard points >= minimumSpacingPoints else { return }
            let end = CGPoint(x: start.x + direction.dx * distance, y: start.y + direction.dy * distance)
            measurements.append(SpacingMeasurement(start: start, end: end, points: points))
        }

        func verticalOverlap(_ rect: CGRect) -> CGFloat {
            min(rect.maxY, element.maxY) - max(rect.minY, element.minY)
        }

        func horizontalOverlap(_ rect: CGRect) -> CGFloat {
            min(rect.maxX, element.maxX) - max(rect.minX, element.minX)
        }

        let leading = (
            rects.compactMap { other -> CGFloat? in
                guard other.maxX <= element.minX + 0.5, verticalOverlap(other) >= minimumFacingOverlap else { return nil }
                return element.minX - other.maxX
            }
            + containers.map { element.minX - $0.minX }
        ).filter { $0 >= 0 }.min()
        appendIfMeaningful(
            distance: leading,
            from: CGPoint(x: element.minX, y: element.midY),
            towards: CGVector(dx: -1, dy: 0)
        )

        let trailing = (
            rects.compactMap { other -> CGFloat? in
                guard other.minX >= element.maxX - 0.5, verticalOverlap(other) >= minimumFacingOverlap else { return nil }
                return other.minX - element.maxX
            }
            + containers.map { $0.maxX - element.maxX }
        ).filter { $0 >= 0 }.min()
        appendIfMeaningful(
            distance: trailing,
            from: CGPoint(x: element.maxX, y: element.midY),
            towards: CGVector(dx: 1, dy: 0)
        )

        let top = (
            rects.compactMap { other -> CGFloat? in
                guard other.maxY <= element.minY + 0.5, horizontalOverlap(other) >= minimumFacingOverlap else { return nil }
                return element.minY - other.maxY
            }
            + containers.map { element.minY - $0.minY }
        ).filter { $0 >= 0 }.min()
        appendIfMeaningful(
            distance: top,
            from: CGPoint(x: element.midX, y: element.minY),
            towards: CGVector(dx: 0, dy: -1)
        )

        let bottom = (
            rects.compactMap { other -> CGFloat? in
                guard other.minY >= element.maxY - 0.5, horizontalOverlap(other) >= minimumFacingOverlap else { return nil }
                return other.minY - element.maxY
            }
            + containers.map { $0.maxY - element.maxY }
        ).filter { $0 >= 0 }.min()
        appendIfMeaningful(
            distance: bottom,
            from: CGPoint(x: element.midX, y: element.maxY),
            towards: CGVector(dx: 0, dy: 1)
        )

        return measurements
    }
}
