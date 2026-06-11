//
//  AnnotationCanvasView.swift
//  DesignReviewKit
//
//  Created by Naveen Gaur on 11/06/2026.
//

import SwiftUI

/// Frozen screenshot with annotation rectangles, drawn and edited by touch.
///
/// Gesture rules:
/// - Drag on empty canvas: draw a new rectangle (anchor-drag marquee).
/// - Tap a rectangle: select it; repeat taps cycle through overlapping rects.
/// - Drag inside the selected rectangle: move it.
/// - Drag a selection handle: resize it.
/// - Tap empty canvas: deselect.
struct AnnotationCanvasView: View {

    let state: InspectorViewModel.AnnotatingState
    let dispatch: (InspectorViewModel.ViewEvent.CanvasEvent) -> Void

    @State
    private var dragMode: DragMode?

    private enum DragMode {
        case drawing(anchor: CGPoint)
        case moving(originalRect: CGRect)
        case resizing(handle: ResizeHandle, originalRect: CGRect)
        case ignored
    }

    private enum Metrics {
        static let handleHitRadius: CGFloat = 22
        static let rectHitSlop: CGFloat = 12
        static let minimumSideInView: CGFloat = 16
        static let badgeDiameter: CGFloat = 24
        static let cornerRadius: CGFloat = 4
    }

    var body: some View {
        GeometryReader { proxy in
            let imageFrame = CGRect.aspectFitRect(
                for: state.imagePointSize,
                in: CGRect(origin: .zero, size: proxy.size)
            )

            ZStack {
                screenshot(in: imageFrame)
                annotationLayer(in: imageFrame)
                inProgressLayer(in: imageFrame)
                selectionLayer(in: imageFrame)
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                handleTap(at: location, imageFrame: imageFrame)
            }
            .gesture(dragGesture(imageFrame: imageFrame))
        }
    }

    // MARK: - Layers

    @ViewBuilder
    private func screenshot(in imageFrame: CGRect) -> some View {
        Group {
            if let image = state.image {
                Image(uiImage: image)
                    .resizable()
            } else {
                // Decode failure: keep the canvas usable with a visible placeholder
                // rather than silently rendering nothing.
                Rectangle()
                    .fill(Color(.secondarySystemBackground))
                    .overlay {
                        Label("Couldn't load capture", systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(width: imageFrame.width, height: imageFrame.height)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.5), lineWidth: 0.5)
        )
        // Layered shadows give the card the soft "paper" depth of Apple's
        // screenshot editor: one tight contact shadow, one diffuse ambient one.
        .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
        .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
        .position(x: imageFrame.midX, y: imageFrame.midY)
    }

    private func annotationLayer(in imageFrame: CGRect) -> some View {
        ForEach(state.annotations) { item in
            let rect = item.normalizedRect.denormalized(in: imageFrame)
            placedRectangle(rect, severity: item.severity, isSelected: item.isSelected)
            numberBadge(item.number, severity: item.severity)
                .position(badgePosition(for: rect, in: imageFrame))
        }
    }

    @ViewBuilder
    private func inProgressLayer(in imageFrame: CGRect) -> some View {
        if let draft = state.draftRect {
            placedRectangle(draft.denormalized(in: imageFrame), severity: .low, isSelected: false)
        }
        if let pending = state.pendingRect {
            placedRectangle(
                pending.normalizedRect.denormalized(in: imageFrame),
                severity: pending.severity,
                isSelected: false
            )
        }
    }

    @ViewBuilder
    private func selectionLayer(in imageFrame: CGRect) -> some View {
        if let selected = state.annotations.first(where: \.isSelected) {
            let rect = selected.normalizedRect.denormalized(in: imageFrame)

            ForEach(ResizeHandle.allCases, id: \.self) { handle in
                Circle()
                    .fill(.white)
                    .strokeBorder(Color(.systemGray3), lineWidth: 1)
                    .frame(width: 12, height: 12)
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                    .position(handle.point(in: rect))
            }

            if dragMode == nil {
                selectionActionBar
                    .position(actionBarPosition(for: rect, in: imageFrame))
            }
        }
    }

    private var selectionActionBar: some View {
        HStack(spacing: 0) {
            Button {
                dispatch(.editCommentTapped)
            } label: {
                Label("Edit Comment", systemImage: "text.bubble")
                    .labelStyle(.iconOnly)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
            }

            Divider()
                .frame(height: 18)

            Button(role: .destructive) {
                dispatch(.deleteSelectedTapped)
            } label: {
                Label("Delete", systemImage: "trash")
                    .labelStyle(.iconOnly)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
            }
        }
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    private func placedRectangle(_ rect: CGRect, severity: Severity, isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous)
            .fill(severity.color.opacity(0.08))
            .strokeBorder(severity.color, lineWidth: isSelected ? 2.5 : 2)
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
    }

    private func numberBadge(_ number: Int, severity: Severity) -> some View {
        Text("\(number)")
            .font(.caption.bold())
            .foregroundStyle(.white)
            .frame(width: Metrics.badgeDiameter, height: Metrics.badgeDiameter)
            .background(severity.color, in: Circle())
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
    }

    // MARK: - Gestures

    private func dragGesture(imageFrame: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                let mode = dragMode ?? determineMode(at: value.startLocation, imageFrame: imageFrame)
                dragMode = mode

                switch mode {
                case .drawing(let anchor):
                    let current = value.location.clamped(to: imageFrame)
                    let rect = CGRect(corner: anchor, opposite: current)
                    dispatch(.drawingUpdated(normalizedRect: rect.normalized(in: imageFrame)))

                case .moving(let originalRect):
                    let moved = originalRect.moved(by: value.translation, within: imageFrame)
                    dispatch(.selectedAnnotationFrameChanged(normalizedRect: moved.normalized(in: imageFrame)))

                case .resizing(let handle, let originalRect):
                    let resized = handle.resizing(
                        originalRect,
                        by: value.translation,
                        minimumSide: Metrics.minimumSideInView,
                        within: imageFrame
                    )
                    dispatch(.selectedAnnotationFrameChanged(normalizedRect: resized.normalized(in: imageFrame)))

                case .ignored:
                    break
                }
            }
            .onEnded { _ in
                if case .drawing = dragMode {
                    dispatch(.drawingEnded)
                }
                dragMode = nil
            }
    }

    /// Resolve what a drag starting at `start` means: resize when it lands on a
    /// selection handle, move when inside the selected rect, draw on empty canvas.
    private func determineMode(at start: CGPoint, imageFrame: CGRect) -> DragMode {
        if let selected = state.annotations.first(where: \.isSelected) {
            let rect = selected.normalizedRect.denormalized(in: imageFrame)

            if let handle = ResizeHandle.allCases.first(where: { handle in
                distance(handle.point(in: rect), start) <= Metrics.handleHitRadius
            }) {
                return .resizing(handle: handle, originalRect: rect)
            }
            if rect.insetBy(dx: -8, dy: -8).contains(start) {
                return .moving(originalRect: rect)
            }
        }

        guard imageFrame.contains(start) else { return .ignored }
        return .drawing(anchor: start)
    }

    private func handleTap(at location: CGPoint, imageFrame: CGRect) {
        // Topmost first: later-created annotations render above earlier ones.
        let candidates = state.annotations.reversed().filter { item in
            item.normalizedRect.denormalized(in: imageFrame)
                .insetBy(dx: -Metrics.rectHitSlop, dy: -Metrics.rectHitSlop)
                .contains(location)
        }

        guard !candidates.isEmpty else {
            dispatch(.emptyAreaTapped)
            return
        }

        // Tapping the already-selected annotation cycles to the one beneath it.
        if let selectedIndex = candidates.firstIndex(where: \.isSelected) {
            let next = candidates[(selectedIndex + 1) % candidates.count]
            dispatch(.annotationTapped(id: next.id))
        } else if let topmost = candidates.first {
            dispatch(.annotationTapped(id: topmost.id))
        }
    }

    // MARK: - Layout Positions

    private func badgePosition(for rect: CGRect, in imageFrame: CGRect) -> CGPoint {
        let radius = Metrics.badgeDiameter / 2
        return CGPoint(x: rect.minX, y: rect.minY)
            .clamped(to: imageFrame.insetBy(dx: radius, dy: radius))
    }

    private func actionBarPosition(for rect: CGRect, in imageFrame: CGRect) -> CGPoint {
        let aboveY = rect.minY - 30
        let y = aboveY > imageFrame.minY + 22 ? aboveY : rect.maxY + 30
        return CGPoint(
            x: min(max(rect.midX, imageFrame.minX + 70), imageFrame.maxX - 70),
            y: y
        )
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}
