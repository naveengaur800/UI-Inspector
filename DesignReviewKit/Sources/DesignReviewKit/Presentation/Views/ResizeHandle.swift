//
//  ResizeHandle.swift
//  DesignReviewKit
//
//  Created by Naveen Gaur on 11/06/2026.
//

import CoreGraphics

/// Resize handles around a selected rectangle: four corners plus four edge midpoints.
nonisolated enum ResizeHandle: CaseIterable {
    case topLeft, top, topRight
    case left, right
    case bottomLeft, bottom, bottomRight

    var movesLeftEdge: Bool {
        switch self {
        case .topLeft, .left, .bottomLeft: true
        default: false
        }
    }

    var movesRightEdge: Bool {
        switch self {
        case .topRight, .right, .bottomRight: true
        default: false
        }
    }

    var movesTopEdge: Bool {
        switch self {
        case .topLeft, .top, .topRight: true
        default: false
        }
    }

    var movesBottomEdge: Bool {
        switch self {
        case .bottomLeft, .bottom, .bottomRight: true
        default: false
        }
    }

    /// Locate this handle on a rectangle's outline.
    func point(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft: CGPoint(x: rect.minX, y: rect.minY)
        case .top: CGPoint(x: rect.midX, y: rect.minY)
        case .topRight: CGPoint(x: rect.maxX, y: rect.minY)
        case .left: CGPoint(x: rect.minX, y: rect.midY)
        case .right: CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomLeft: CGPoint(x: rect.minX, y: rect.maxY)
        case .bottom: CGPoint(x: rect.midX, y: rect.maxY)
        case .bottomRight: CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }

    /// Resize `rect` by a drag translation on this handle, keeping each side at
    /// least `minimumSide` and every edge inside `bounds`.
    func resizing(_ rect: CGRect, by translation: CGSize, minimumSide: CGFloat, within bounds: CGRect) -> CGRect {
        var minX = rect.minX
        var maxX = rect.maxX
        var minY = rect.minY
        var maxY = rect.maxY

        if movesLeftEdge {
            minX = min(maxX - minimumSide, max(bounds.minX, minX + translation.width))
        }
        if movesRightEdge {
            maxX = max(minX + minimumSide, min(bounds.maxX, maxX + translation.width))
        }
        if movesTopEdge {
            minY = min(maxY - minimumSide, max(bounds.minY, minY + translation.height))
        }
        if movesBottomEdge {
            maxY = max(minY + minimumSide, min(bounds.maxY, maxY + translation.height))
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

nonisolated extension CGRect {

    /// Build a rect spanning two diagonal corners, whatever direction the drag went.
    init(corner: CGPoint, opposite: CGPoint) {
        self.init(
            x: min(corner.x, opposite.x),
            y: min(corner.y, opposite.y),
            width: abs(opposite.x - corner.x),
            height: abs(opposite.y - corner.y)
        )
    }

    /// Translate the rect, clamped so it stays entirely inside `bounds`.
    func moved(by translation: CGSize, within bounds: CGRect) -> CGRect {
        var moved = offsetBy(dx: translation.width, dy: translation.height)
        moved.origin.x = min(max(moved.origin.x, bounds.minX), bounds.maxX - moved.width)
        moved.origin.y = min(max(moved.origin.y, bounds.minY), bounds.maxY - moved.height)
        return moved
    }
}
