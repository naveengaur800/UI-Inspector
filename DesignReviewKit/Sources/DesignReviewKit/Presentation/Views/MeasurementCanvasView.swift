//
//  MeasurementCanvasView.swift
//  DesignReviewKit
//
//  Created by Naveen Gaur on 11/06/2026.
//

import SwiftUI
import UIKit

/// Distance-measuring overlay: drag between two points to read the gap in
/// screenshot points. Endpoints snap to nearby element edges — a red guide
/// lights up along the snapped edge, with a haptic tick, so it's clear the
/// drag has landed exactly on it. Near-axis drags lock to the axis.
/// Long-press an element for a glass menu; choosing Spacing flashes the
/// distances from its edges to the nearest neighboring elements (or its
/// container), fading on their own.
///
/// Measurements are transient tooling — they live only in this view's state
/// and never enter the session, the annotations, or the PDF report.
struct MeasurementCanvasView: View {

    let imagePointSize: CGSize
    /// Element frames in unit coordinates; endpoints snap to their edges.
    let elementFrames: [CGRect]

    @State
    private var measurement: Measurement?

    @State
    private var spacingReadout: ElementSpacingReadout?

    @State
    private var pendingSpacingMenu: PendingSpacingMenu?

    /// Long-press result staged behind the glass menu: the readout is computed
    /// up front so the menu only appears where Spacing has something to show.
    private struct PendingSpacingMenu {
        let location: CGPoint
        let readout: ElementSpacingReadout
    }

    @State
    private var snapHaptics = UISelectionFeedbackGenerator()

    @State
    private var spacingHaptics = UIImpactFeedbackGenerator(style: .light)

    private struct Measurement {
        var start: CGPoint
        var end: CGPoint
        var guides: [EdgeGuide]
    }

    /// The full element edge an endpoint snapped onto, drawn as a guide line.
    private struct EdgeGuide: Equatable {
        let start: CGPoint
        let end: CGPoint
    }

    /// A snapped endpoint plus the edges that captured it, per axis, so axis
    /// locking can revoke one without losing the other.
    private struct SnapResult {
        var point: CGPoint
        var verticalEdgeGuide: EdgeGuide?
        var horizontalEdgeGuide: EdgeGuide?
    }

    private enum Metrics {
        static let snapDistance: CGFloat = 8
        static let axisLockTolerance: CGFloat = 10
        static let endTickLength: CGFloat = 10
        static let labelLift: CGFloat = 18
    }

    var body: some View {
        GeometryReader { proxy in
            let imageFrame = CGRect.aspectFitRect(
                for: imagePointSize,
                in: CGRect(origin: .zero, size: proxy.size)
            )

            ZStack {
                if let spacingReadout {
                    spacingReadoutView(spacingReadout)
                }

                if let measurement {
                    ForEach(Array(measurement.guides.enumerated()), id: \.offset) { _, guide in
                        edgeGuideLine(guide)
                    }
                    measurementLine(measurement)
                    distanceLabel(measurement, imageFrame: imageFrame)
                }

                if let pendingSpacingMenu {
                    spacingMenu(pendingSpacingMenu, imageFrame: imageFrame)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                dismissSpacingMenu()
            }
            .gesture(measureGesture(imageFrame: imageFrame))
            .simultaneousGesture(spacingGesture(imageFrame: imageFrame))
        }
        .task(id: spacingReadout) {
            // Let the readout breathe, then fade it out on its own.
            guard spacingReadout != nil else { return }
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation(.easeOut(duration: 0.4)) {
                spacingReadout = nil
            }
        }
    }

    // MARK: - Gesture

    private func measureGesture(imageFrame: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                dismissSpacingMenu()
                let snapTargets = elementFrames.map { $0.denormalized(in: imageFrame) }
                let startSnap = snapped(value.startLocation.clamped(to: imageFrame), to: snapTargets)
                var endSnap = snapped(value.location.clamped(to: imageFrame), to: snapTargets)
                applyAxisLock(to: &endSnap, relativeTo: startSnap.point)

                let guides = [
                    startSnap.verticalEdgeGuide, startSnap.horizontalEdgeGuide,
                    endSnap.verticalEdgeGuide, endSnap.horizontalEdgeGuide,
                ].compactMap(\.self)

                // Tick when a new edge engages, so reaching an edge is felt, not just seen.
                if !guides.isEmpty, guides != measurement?.guides {
                    snapHaptics.selectionChanged()
                }

                measurement = Measurement(start: startSnap.point, end: endSnap.point, guides: guides)
            }
    }

    /// Snap each axis independently to the nearest element edge within range,
    /// recording the captured edge so it can be drawn as a guide.
    private func snapped(_ point: CGPoint, to targets: [CGRect]) -> SnapResult {
        var result = SnapResult(point: point, verticalEdgeGuide: nil, horizontalEdgeGuide: nil)
        var nearestX = Metrics.snapDistance
        var nearestY = Metrics.snapDistance

        for target in targets {
            if point.y >= target.minY - Metrics.snapDistance,
               point.y <= target.maxY + Metrics.snapDistance {
                for edgeX in [target.minX, target.maxX] where abs(edgeX - point.x) < nearestX {
                    nearestX = abs(edgeX - point.x)
                    result.point.x = edgeX
                    result.verticalEdgeGuide = EdgeGuide(
                        start: CGPoint(x: edgeX, y: target.minY),
                        end: CGPoint(x: edgeX, y: target.maxY)
                    )
                }
            }
            if point.x >= target.minX - Metrics.snapDistance,
               point.x <= target.maxX + Metrics.snapDistance {
                for edgeY in [target.minY, target.maxY] where abs(edgeY - point.y) < nearestY {
                    nearestY = abs(edgeY - point.y)
                    result.point.y = edgeY
                    result.horizontalEdgeGuide = EdgeGuide(
                        start: CGPoint(x: target.minX, y: edgeY),
                        end: CGPoint(x: target.maxX, y: edgeY)
                    )
                }
            }
        }
        return result
    }

    /// Hold the line to an axis when the drag is nearly horizontal or vertical.
    /// A coordinate the lock overrides loses its guide — a visible guide always
    /// means the endpoint sits exactly on that edge.
    private func applyAxisLock(to snap: inout SnapResult, relativeTo start: CGPoint) {
        let deltaX = abs(snap.point.x - start.x)
        let deltaY = abs(snap.point.y - start.y)

        if deltaY < Metrics.axisLockTolerance, deltaX > Metrics.axisLockTolerance {
            if snap.point.y != start.y {
                snap.point.y = start.y
                snap.horizontalEdgeGuide = nil
            }
        } else if deltaX < Metrics.axisLockTolerance, deltaY > Metrics.axisLockTolerance {
            if snap.point.x != start.x {
                snap.point.x = start.x
                snap.verticalEdgeGuide = nil
            }
        }
    }

    // MARK: - Spacing Readout

    private func spacingGesture(imageFrame: CGRect) -> some Gesture {
        LongPressGesture(minimumDuration: 0.4)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
            .onChanged { value in
                guard case .second(true, let drag?) = value else { return }
                presentSpacingMenu(at: drag.startLocation, imageFrame: imageFrame)
            }
            .onEnded { value in
                guard case .second(true, let drag?) = value else { return }
                presentSpacingMenu(at: drag.startLocation, imageFrame: imageFrame)
            }
    }

    private func presentSpacingMenu(at location: CGPoint, imageFrame: CGRect) {
        guard pendingSpacingMenu?.location != location else { return }

        let elementRects = elementFrames.map { $0.denormalized(in: imageFrame) }
        let pointsPerViewUnit = imageFrame.width > 0 ? imagePointSize.width / imageFrame.width : 1
        guard let readout = ElementSpacingCalculator.readout(
            at: location,
            elementRects: elementRects,
            bounds: imageFrame,
            pointsPerViewUnit: pointsPerViewUnit
        ) else { return }

        spacingHaptics.impactOccurred()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            pendingSpacingMenu = PendingSpacingMenu(location: location, readout: readout)
        }
    }

    private func dismissSpacingMenu() {
        guard pendingSpacingMenu != nil else { return }
        withAnimation(.easeOut(duration: 0.15)) {
            pendingSpacingMenu = nil
        }
    }

    private func spacingMenu(_ menu: PendingSpacingMenu, imageFrame: CGRect) -> some View {
        Button {
            withAnimation(.easeIn(duration: 0.15)) {
                spacingReadout = menu.readout
                pendingSpacingMenu = nil
            }
        } label: {
            Label("Spacing", systemImage: "ruler")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .position(menuPosition(for: menu.location, in: imageFrame))
        .transition(.scale(scale: 0.85).combined(with: .opacity))
    }

    /// Float the menu just above the finger, clamped inside the capture.
    private func menuPosition(for pressLocation: CGPoint, in imageFrame: CGRect) -> CGPoint {
        CGPoint(x: pressLocation.x, y: pressLocation.y - 44)
            .clamped(to: imageFrame.insetBy(dx: 60, dy: 30))
    }

    private func spacingReadoutView(_ readout: ElementSpacingReadout) -> some View {
        ZStack {
            Path { $0.addRect(readout.elementRect) }
                .stroke(Color.accentColor.opacity(0.7), lineWidth: 1)

            ForEach(Array(readout.measurements.enumerated()), id: \.offset) { _, spacing in
                spacingLine(spacing)
                spacingLabel(spacing)
            }
        }
        .transition(.opacity)
    }

    private func spacingLine(_ spacing: SpacingMeasurement) -> some View {
        Path { path in
            path.move(to: spacing.start)
            path.addLine(to: spacing.end)

            let tick = tickOffset(from: spacing.start, to: spacing.end)
            for endpoint in [spacing.start, spacing.end] {
                path.move(to: CGPoint(x: endpoint.x - tick.dx, y: endpoint.y - tick.dy))
                path.addLine(to: CGPoint(x: endpoint.x + tick.dx, y: endpoint.y + tick.dy))
            }
        }
        .stroke(Color.accentColor, lineWidth: 1)
    }

    private func spacingLabel(_ spacing: SpacingMeasurement) -> some View {
        let isHorizontal = abs(spacing.end.x - spacing.start.x) >= abs(spacing.end.y - spacing.start.y)

        return Text("\(Int(spacing.points.rounded()))")
            .font(.caption2.bold().monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.9), in: Capsule())
            .position(
                x: (spacing.start.x + spacing.end.x) / 2 + (isHorizontal ? 0 : 16),
                y: (spacing.start.y + spacing.end.y) / 2 + (isHorizontal ? -11 : 0)
            )
    }

    // MARK: - Rendering

    /// Full-edge guide showing exactly which element edge captured the endpoint.
    private func edgeGuideLine(_ guide: EdgeGuide) -> some View {
        Path { path in
            path.move(to: guide.start)
            path.addLine(to: guide.end)
        }
        .stroke(Color.red.opacity(0.8), lineWidth: 1)
    }

    /// Caliper-style line: the measured span with perpendicular ticks at both ends.
    private func measurementLine(_ measurement: Measurement) -> some View {
        Path { path in
            path.move(to: measurement.start)
            path.addLine(to: measurement.end)

            let tick = tickOffset(from: measurement.start, to: measurement.end)
            for endpoint in [measurement.start, measurement.end] {
                path.move(to: CGPoint(x: endpoint.x - tick.dx, y: endpoint.y - tick.dy))
                path.addLine(to: CGPoint(x: endpoint.x + tick.dx, y: endpoint.y + tick.dy))
            }
        }
        .stroke(Color.accentColor, lineWidth: 1.5)
    }

    /// Half-tick vector perpendicular to the line between two points.
    private func tickOffset(from start: CGPoint, to end: CGPoint) -> CGVector {
        let deltaX = end.x - start.x
        let deltaY = end.y - start.y
        let length = max(hypot(deltaX, deltaY), 0.001)
        let halfTick = Metrics.endTickLength / 2
        return CGVector(dx: -deltaY / length * halfTick, dy: deltaX / length * halfTick)
    }

    private func distanceLabel(_ measurement: Measurement, imageFrame: CGRect) -> some View {
        let viewDistance = hypot(
            measurement.end.x - measurement.start.x,
            measurement.end.y - measurement.start.y
        )
        // Convert from on-screen distance to true capture points: the card
        // renders the screenshot scaled down, the designer cares about pt.
        let captureScale = imageFrame.width > 0 ? imagePointSize.width / imageFrame.width : 1
        let capturePoints = Int((viewDistance * captureScale).rounded())

        return Text("\(capturePoints) pt")
            .font(.caption.bold().monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.accentColor, in: Capsule())
            .position(
                x: (measurement.start.x + measurement.end.x) / 2,
                y: (measurement.start.y + measurement.end.y) / 2 - Metrics.labelLift
            )
    }
}
