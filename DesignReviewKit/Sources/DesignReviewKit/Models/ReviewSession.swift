//
//  ReviewSession.swift
//  DesignReviewKit
//
//  Created by Naveen Gaur on 11/06/2026.
//

import Foundation

/// One feedback session: every screen the designer captured and annotated, plus report metadata.
nonisolated struct ReviewSession: Sendable {
    let startedAt: Date
    let appMetadata: AppMetadata
    let deviceMetadata: DeviceMetadata
    var screens: [CapturedScreen]

    /// An annotation paired with its session-wide issue number and owning screen.
    struct NumberedIssue: Sendable {
        let number: Int
        let screenID: UUID
        let screenIndex: Int
        let annotation: Annotation
    }

    /// Order every annotation across all screens by creation time and number them 1…n.
    /// Numbers are always derived, never stored — deleting an annotation renumbers automatically.
    var numberedIssues: [NumberedIssue] {
        screens.enumerated()
            .flatMap { index, screen in
                screen.annotations.map { (screenIndex: index, screenID: screen.id, annotation: $0) }
            }
            .sorted { $0.annotation.createdAt < $1.annotation.createdAt }
            .enumerated()
            .map { offset, issue in
                NumberedIssue(
                    number: offset + 1,
                    screenID: issue.screenID,
                    screenIndex: issue.screenIndex,
                    annotation: issue.annotation
                )
            }
    }

    var issueCount: Int {
        screens.reduce(0) { $0 + $1.annotations.count }
    }

    /// - Returns: The session-wide issue number for an annotation, or `nil` if it no longer exists.
    func issueNumber(for annotationID: UUID) -> Int? {
        numberedIssues.first { $0.annotation.id == annotationID }?.number
    }

    func count(of severity: Severity) -> Int {
        screens.reduce(0) { total, screen in
            total + screen.annotations.count { $0.severity == severity }
        }
    }
}

// MARK: - Lookups

extension ReviewSession {

    /// - Returns: The annotation with `id`, or `nil` if it no longer exists.
    func annotation(id: UUID) -> Annotation? {
        screens.lazy
            .compactMap { screen in screen.annotations.first { $0.id == id } }
            .first
    }

    /// - Returns: The screen an annotation lives on, or `nil` if it no longer exists.
    func screen(containingAnnotation id: UUID) -> CapturedScreen? {
        screens.first { screen in
            screen.annotations.contains { $0.id == id }
        }
    }
}

// MARK: - Mutations

extension ReviewSession {

    /// Add an annotation to a screen.
    mutating func addAnnotation(_ annotation: Annotation, toScreenID screenID: UUID) {
        guard let index = screens.firstIndex(where: { $0.id == screenID }) else { return }
        screens[index].annotations.append(annotation)
    }

    /// Mutate an annotation wherever it lives.
    mutating func updateAnnotation(id: UUID, _ mutate: (inout Annotation) -> Void) {
        for screenIndex in screens.indices {
            guard let annotationIndex = screens[screenIndex].annotations.firstIndex(where: { $0.id == id }) else {
                continue
            }
            mutate(&screens[screenIndex].annotations[annotationIndex])
            return
        }
    }

    /// Remove an annotation wherever it lives. Issue numbers renumber automatically
    /// because they're always derived from creation order.
    mutating func removeAnnotation(id: UUID) {
        for index in screens.indices {
            screens[index].annotations.removeAll { $0.id == id }
        }
    }

    /// Remove annotation-less screens so accidental captures don't linger.
    ///
    /// - Returns: IDs of the removed screens, for cache eviction.
    @discardableResult
    mutating func removeEmptyScreens() -> [UUID] {
        let emptyScreenIDs = screens.filter(\.annotations.isEmpty).map(\.id)
        screens.removeAll(where: \.annotations.isEmpty)
        return emptyScreenIDs
    }
}
