//
//  View+DesignInspector.swift
//  DesignReviewKit
//
//  Created by Naveen Gaur on 11/06/2026.
//

import SwiftUI

private struct DesignInspectorKey: EnvironmentKey {
    static let defaultValue: DesignInspector? = nil
}

public extension EnvironmentValues {
    /// Inspector injected by the host's composition root; `nil` where none is installed.
    var designInspector: DesignInspector? {
        get { self[DesignInspectorKey.self] }
        set { self[DesignInspectorKey.self] = newValue }
    }
}

public extension View {
    /// Install the inspector so descendant views can reach it via
    /// `@Environment(\.designInspector)` and wire their own trigger.
    func designInspector(_ inspector: DesignInspector) -> some View {
        environment(\.designInspector, inspector)
    }
}
