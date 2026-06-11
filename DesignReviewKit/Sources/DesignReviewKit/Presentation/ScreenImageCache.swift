//
//  ScreenImageCache.swift
//  DesignReviewKit
//
//  Created by Naveen Gaur on 11/06/2026.
//

import UIKit

/// Decode captured screens on demand and memoize the results, so the canvas,
/// thumbnail strip, and review crops share one decode per screen.
final class ScreenImageCache {

    private var imagesByScreenID: [UUID: UIImage] = [:]

    /// Decode the screen's stored capture, returning the cached result on repeat calls.
    func image(for screen: CapturedScreen) -> UIImage? {
        if let cached = imagesByScreenID[screen.id] {
            return cached
        }
        let image = screen.makeImage()
        imagesByScreenID[screen.id] = image
        return image
    }

    /// Drop the cached decodes for screens that left the session.
    func removeImages(forScreenIDs screenIDs: [UUID]) {
        for screenID in screenIDs {
            imagesByScreenID[screenID] = nil
        }
    }
}
