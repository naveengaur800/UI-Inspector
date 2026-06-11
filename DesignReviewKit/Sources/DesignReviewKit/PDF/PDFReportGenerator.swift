//
//  PDFReportGenerator.swift
//  DesignReviewKit
//
//  Created by Naveen Gaur on 11/06/2026.
//

import CoreText
import UIKit

/// Render a review session into a landscape A4 PDF report.
///
/// Document structure: a cover page with session metadata and severity counts,
/// then one page per issue — full screenshot on the left with this issue's rectangle
/// at full strength and siblings ghosted, commentary on the right. Long comments
/// continue on follow-on pages. Rectangles and badges are drawn vectorially from
/// stored geometry so they stay crisp at any zoom.
nonisolated struct PDFReportGenerator {

    enum GenerationError: Error {
        case emptySession
        case imageDecodingFailed
    }

    // MARK: - Layout

    private enum Layout {
        /// Landscape A4 in PDF points.
        static let pageRect = CGRect(x: 0, y: 0, width: 842, height: 595)
        static let margin: CGFloat = 36
        static let headerHeight: CGFloat = 48
        static let footerHeight: CGFloat = 26
        static let columnGap: CGFloat = 24
        /// Fraction of the content width given to the screenshot column.
        static let imageColumnFraction: CGFloat = 0.45
        static let metaRowHeight: CGFloat = 22
        static let ghostAlpha: CGFloat = 0.25

        static var contentRect: CGRect {
            pageRect.insetBy(dx: margin, dy: margin)
        }

        static var bodyRect: CGRect {
            CGRect(
                x: contentRect.minX,
                y: contentRect.minY + headerHeight,
                width: contentRect.width,
                height: contentRect.height - headerHeight - footerHeight
            )
        }

        static var imageColumnRect: CGRect {
            CGRect(
                x: bodyRect.minX,
                y: bodyRect.minY,
                width: bodyRect.width * imageColumnFraction - columnGap / 2,
                height: bodyRect.height
            )
        }

        static var commentColumnRect: CGRect {
            let imageColumn = imageColumnRect
            return CGRect(
                x: imageColumn.maxX + columnGap,
                y: bodyRect.minY,
                width: bodyRect.width - imageColumn.width - columnGap,
                height: bodyRect.height
            )
        }
    }

    private enum PageSpec {
        case cover
        case issue(IssuePageSpec)
    }

    private struct IssuePageSpec {
        let issue: ReviewSession.NumberedIssue
        let textChunk: NSAttributedString
        let isContinuation: Bool
    }

    // MARK: - Generation

    /// Render the session into a temporary PDF file.
    /// - Returns: File URL of the generated report.
    func generateReport(for session: ReviewSession) async throws -> URL {
        guard session.issueCount > 0 else { throw GenerationError.emptySession }

        let issues = session.numberedIssues
        // One pass over the numbering; per-annotation lookups while drawing would be O(n²).
        let issueNumbers = Dictionary(uniqueKeysWithValues: issues.map { ($0.annotation.id, $0.number) })
        let images = try decodeImages(for: session, issues: issues)
        let pages = buildPageSpecs(for: issues)
        let url = reportFileURL(for: session)

        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: "\(session.appMetadata.name) — Design Review",
            kCGPDFContextCreator as String: "DesignReviewKit",
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: Layout.pageRect, format: format)

        try renderer.writePDF(to: url) { context in
            for (index, page) in pages.enumerated() {
                context.beginPage()
                switch page {
                case .cover:
                    drawCoverPage(session: session)
                case .issue(let spec):
                    drawIssuePage(
                        spec,
                        session: session,
                        images: images,
                        issueNumbers: issueNumbers
                    )
                }
                drawFooter(session: session, pageNumber: index + 1, totalPages: pages.count)
            }
        }

        return url
    }

    // MARK: - Page Building

    private func buildPageSpecs(for issues: [ReviewSession.NumberedIssue]) -> [PageSpec] {
        var pages: [PageSpec] = [.cover]

        let firstPageTextSize = CGSize(
            width: Layout.commentColumnRect.width,
            height: Layout.commentColumnRect.height - Layout.metaRowHeight
        )
        let continuationTextSize = Layout.bodyRect.size

        for issue in issues {
            let comment = attributedComment(issue.annotation.comment)
            let chunks = paginate(comment, firstSize: firstPageTextSize, continuationSize: continuationTextSize)
            for (chunkIndex, chunk) in chunks.enumerated() {
                pages.append(.issue(IssuePageSpec(
                    issue: issue,
                    textChunk: chunk,
                    isContinuation: chunkIndex > 0
                )))
            }
        }

        return pages
    }

    /// Split text into ranges that fit the first page's comment column, then full-width
    /// continuation pages, using CoreText's visible-range measurement.
    private func paginate(
        _ text: NSAttributedString,
        firstSize: CGSize,
        continuationSize: CGSize
    ) -> [NSAttributedString] {
        guard text.length > 0 else { return [text] }

        let framesetter = CTFramesetterCreateWithAttributedString(text)
        var chunks: [NSAttributedString] = []
        var location = 0
        var frameSize = firstSize

        while location < text.length {
            let path = CGPath(rect: CGRect(origin: .zero, size: frameSize), transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: location, length: 0), path, nil)
            let visibleRange = CTFrameGetVisibleStringRange(frame)
            guard visibleRange.length > 0 else { break }

            chunks.append(text.attributedSubstring(from: NSRange(location: location, length: visibleRange.length)))
            location += visibleRange.length
            frameSize = continuationSize
        }

        return chunks.isEmpty ? [text] : chunks
    }

    private func decodeImages(
        for session: ReviewSession,
        issues: [ReviewSession.NumberedIssue]
    ) throws -> [UUID: UIImage] {
        let screenIDsWithIssues = Set(issues.map(\.screenID))
        var images: [UUID: UIImage] = [:]
        for screen in session.screens where screenIDsWithIssues.contains(screen.id) {
            guard let image = screen.makeImage() else { throw GenerationError.imageDecodingFailed }
            images[screen.id] = image
        }
        return images
    }

    // MARK: - Cover Page

    private func drawCoverPage(session: ReviewSession) {
        let content = Layout.contentRect
        var cursorY = content.minY + 40

        cursorY += draw("Design Review", at: CGPoint(x: content.minX, y: cursorY), font: .systemFont(ofSize: 34, weight: .bold), color: .black) + 6
        cursorY += draw(session.appMetadata.name, at: CGPoint(x: content.minX, y: cursorY), font: .systemFont(ofSize: 21, weight: .semibold), color: .darkGray) + 4
        cursorY += draw(sessionDateString(session.startedAt), at: CGPoint(x: content.minX, y: cursorY), font: .systemFont(ofSize: 13), color: .gray) + 36

        let metadataRows: [(String, String)] = [
            ("Version", "\(session.appMetadata.version) (\(session.appMetadata.build))"),
            ("Device", session.deviceMetadata.model),
            ("System", session.deviceMetadata.system),
            ("Screen", screenSizeString(session.deviceMetadata)),
        ]
        for (label, value) in metadataRows {
            draw(label, at: CGPoint(x: content.minX, y: cursorY), font: .systemFont(ofSize: 12, weight: .medium), color: .gray)
            draw(value, at: CGPoint(x: content.minX + 110, y: cursorY), font: .systemFont(ofSize: 12), color: .black)
            cursorY += 22
        }
        cursorY += 30

        let screenCount = session.screens.count { !$0.annotations.isEmpty }
        let screenWord = screenCount == 1 ? "screen" : "screens"
        let issueWord = session.issueCount == 1 ? "issue" : "issues"
        cursorY += draw(
            "\(session.issueCount) \(issueWord) across \(screenCount) \(screenWord)",
            at: CGPoint(x: content.minX, y: cursorY),
            font: .systemFont(ofSize: 17, weight: .semibold),
            color: .black
        ) + 14

        var chipX = content.minX
        for severity in Severity.reportOrder {
            let count = session.count(of: severity)
            guard count > 0 else { continue }
            let chipRect = drawChip(
                text: "\(count) \(severity.displayName)",
                color: reportColor(for: severity),
                topLeft: CGPoint(x: chipX, y: cursorY)
            )
            chipX = chipRect.maxX + 10
        }
    }

    // MARK: - Issue Page

    private func drawIssuePage(
        _ spec: IssuePageSpec,
        session: ReviewSession,
        images: [UUID: UIImage],
        issueNumbers: [UUID: Int]
    ) {
        let issue = spec.issue
        let content = Layout.contentRect

        var headerTitle = "Issue #\(issue.number) · Screen \(issue.screenIndex + 1)"
        if spec.isContinuation {
            headerTitle += " · continued"
        }
        draw(headerTitle, at: CGPoint(x: content.minX, y: content.minY + 8), font: .systemFont(ofSize: 20, weight: .semibold), color: .black)
        drawChip(
            text: issue.annotation.severity.displayName.uppercased(),
            color: reportColor(for: issue.annotation.severity),
            topRight: CGPoint(x: content.maxX, y: content.minY + 10)
        )

        if spec.isContinuation {
            spec.textChunk.draw(
                with: Layout.bodyRect,
                options: [.usesLineFragmentOrigin],
                context: nil
            )
            return
        }

        if let screen = session.screens.first(where: { $0.id == issue.screenID }),
           let image = images[issue.screenID] {
            drawScreenshot(image, screen: screen, focusedAnnotationID: issue.annotation.id, issueNumbers: issueNumbers)
        }

        let commentColumn = Layout.commentColumnRect
        draw(
            "Captured \(captureTimeString(issue, in: session))",
            at: CGPoint(x: commentColumn.minX, y: commentColumn.minY),
            font: .systemFont(ofSize: 11),
            color: .gray
        )
        spec.textChunk.draw(
            with: CGRect(
                x: commentColumn.minX,
                y: commentColumn.minY + Layout.metaRowHeight,
                width: commentColumn.width,
                height: commentColumn.height - Layout.metaRowHeight
            ),
            options: [.usesLineFragmentOrigin],
            context: nil
        )
    }

    private func drawScreenshot(
        _ image: UIImage,
        screen: CapturedScreen,
        focusedAnnotationID: UUID,
        issueNumbers: [UUID: Int]
    ) {
        let column = Layout.imageColumnRect
        let imageRect = CGRect.aspectFitRect(for: screen.imagePointSize, in: column)
        image.draw(in: imageRect)

        for annotation in screen.annotations {
            let isFocused = annotation.id == focusedAnnotationID
            let alpha = isFocused ? 1 : Layout.ghostAlpha
            let rect = annotation.normalizedRect.denormalized(in: imageRect)
            let color = reportColor(for: annotation.severity)

            let path = UIBezierPath(roundedRect: rect, cornerRadius: 3)
            color.withAlphaComponent(alpha * 0.08).setFill()
            path.fill()
            color.withAlphaComponent(alpha).setStroke()
            path.lineWidth = isFocused ? 1.8 : 1.2
            path.stroke()

            if let number = issueNumbers[annotation.id] {
                drawBadge(number: number, color: color, alpha: alpha, corner: rect.origin, within: imageRect)
            }
        }
    }

    private func drawBadge(number: Int, color: UIColor, alpha: CGFloat, corner: CGPoint, within bounds: CGRect) {
        let diameter: CGFloat = 16
        let radius = diameter / 2
        let center = corner.clamped(to: bounds.insetBy(dx: radius, dy: radius))
        let badgeRect = CGRect(x: center.x - radius, y: center.y - radius, width: diameter, height: diameter)

        color.withAlphaComponent(alpha).setFill()
        UIBezierPath(ovalIn: badgeRect).fill()

        let text = NSAttributedString(string: "\(number)", attributes: [
            .font: UIFont.systemFont(ofSize: 9, weight: .bold),
            .foregroundColor: UIColor.white.withAlphaComponent(alpha),
        ])
        let textSize = text.size()
        text.draw(at: CGPoint(
            x: badgeRect.midX - textSize.width / 2,
            y: badgeRect.midY - textSize.height / 2
        ))
    }

    // MARK: - Footer

    private func drawFooter(session: ReviewSession, pageNumber: Int, totalPages: Int) {
        let text = NSAttributedString(
            string: "\(session.appMetadata.name) — Design Review · Page \(pageNumber) of \(totalPages)",
            attributes: [
                .font: UIFont.systemFont(ofSize: 9),
                .foregroundColor: UIColor.gray,
            ]
        )
        let size = text.size()
        text.draw(at: CGPoint(
            x: Layout.pageRect.midX - size.width / 2,
            y: Layout.pageRect.maxY - Layout.margin + 10
        ))
    }

    // MARK: - Drawing Helpers

    /// Draw single-line text and return its height.
    @discardableResult
    private func draw(_ string: String, at point: CGPoint, font: UIFont, color: UIColor) -> CGFloat {
        let text = NSAttributedString(string: string, attributes: [
            .font: font,
            .foregroundColor: color,
        ])
        text.draw(at: point)
        return text.size().height
    }

    @discardableResult
    private func drawChip(text: String, color: UIColor, topLeft: CGPoint? = nil, topRight: CGPoint? = nil) -> CGRect {
        let attributed = NSAttributedString(string: text, attributes: [
            .font: UIFont.systemFont(ofSize: 11, weight: .bold),
            .foregroundColor: UIColor.white,
        ])
        let textSize = attributed.size()
        let chipSize = CGSize(width: textSize.width + 18, height: textSize.height + 8)

        let origin: CGPoint
        if let topLeft {
            origin = topLeft
        } else if let topRight {
            origin = CGPoint(x: topRight.x - chipSize.width, y: topRight.y)
        } else {
            origin = .zero
        }

        let chipRect = CGRect(origin: origin, size: chipSize)
        color.setFill()
        UIBezierPath(roundedRect: chipRect, cornerRadius: chipSize.height / 2).fill()
        attributed.draw(at: CGPoint(x: chipRect.minX + 9, y: chipRect.minY + 4))
        return chipRect
    }

    /// Resolve a severity color for the always-white PDF page — generating from a
    /// dark-mode device must not bake in the dark variants of the system colors.
    private func reportColor(for severity: Severity) -> UIColor {
        severity.uiColor.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
    }

    private func attributedComment(_ comment: String) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4
        paragraphStyle.paragraphSpacing = 8
        return NSAttributedString(string: comment, attributes: [
            .font: UIFont.systemFont(ofSize: 13),
            .foregroundColor: UIColor(white: 0.15, alpha: 1),
            .paragraphStyle: paragraphStyle,
        ])
    }

    // MARK: - Formatting

    private func sessionDateString(_ date: Date) -> String {
        date.formatted(date: .long, time: .shortened)
    }

    private func captureTimeString(_ issue: ReviewSession.NumberedIssue, in session: ReviewSession) -> String {
        guard let screen = session.screens.first(where: { $0.id == issue.screenID }) else { return "—" }
        return screen.capturedAt.formatted(date: .omitted, time: .shortened)
    }

    private func screenSizeString(_ metadata: DeviceMetadata) -> String {
        let width = Int(metadata.screenPointSize.width)
        let height = Int(metadata.screenPointSize.height)
        let scale = Int(metadata.displayScale)
        return "\(width) × \(height) pt @\(scale)x"
    }

    private func reportFileURL(for session: ReviewSession) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        let timestamp = formatter.string(from: Date())

        let sanitizedAppName = session.appMetadata.name
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")

        return FileManager.default.temporaryDirectory
            .appendingPathComponent("DesignReview-\(sanitizedAppName)-\(timestamp)")
            .appendingPathExtension("pdf")
    }
}
